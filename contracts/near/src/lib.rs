//! Flutter Counter on NEAR.
//!
//! Each account (the transaction's predecessor) has its own counter. The
//! contract also counts how many accounts have ever used it. Events follow
//! NEP-297, so indexers and the app can read them from transaction logs.
use near_sdk::{env, near, store::LookupMap, AccountId, BorshStorageKey};

#[near]
#[derive(BorshStorageKey)]
enum StorageKey {
    Counters,
}

#[near(contract_state)]
pub struct Contract {
    counters: LookupMap<AccountId, i64>,
    total_users: u64,
}

impl Default for Contract {
    fn default() -> Self {
        Self { counters: LookupMap::new(StorageKey::Counters), total_users: 0 }
    }
}

#[near(event_json(standard = "flutter_counter"))]
pub enum CounterEvent {
    #[event_version("1.0.0")]
    UserRegistered { user: AccountId, total_users: u64 },
    #[event_version("1.0.0")]
    CounterChanged { user: AccountId, old_value: i64, new_value: i64, action: String },
}

#[near]
impl Contract {
    /// Adds one to the caller's counter and returns the new value.
    pub fn increment(&mut self) -> i64 {
        let old = self.current();
        self.set(old.checked_add(1).expect("counter overflow"), "increment")
    }

    /// Subtracts one from the caller's counter and returns the new value.
    pub fn decrement(&mut self) -> i64 {
        let old = self.current();
        self.set(old.checked_sub(1).expect("counter overflow"), "decrement")
    }

    /// Sets the caller's counter back to zero.
    pub fn reset(&mut self) -> i64 {
        self.set(0, "reset")
    }

    /// An account's counter. Accounts that never called the contract read as 0.
    pub fn get_value(&self, account_id: AccountId) -> i64 {
        self.counters.get(&account_id).copied().unwrap_or(0)
    }

    pub fn is_user(&self, account_id: AccountId) -> bool {
        self.counters.contains_key(&account_id)
    }

    pub fn total_users(&self) -> u64 {
        self.total_users
    }

    fn current(&self) -> i64 {
        self.get_value(env::predecessor_account_id())
    }

    fn set(&mut self, new_value: i64, action: &str) -> i64 {
        let user = env::predecessor_account_id();
        let old_value = self.current();
        if !self.counters.contains_key(&user) {
            self.total_users += 1;
            CounterEvent::UserRegistered { user: user.clone(), total_users: self.total_users }.emit();
        }
        self.counters.insert(user.clone(), new_value);
        CounterEvent::CounterChanged { user, old_value, new_value, action: action.to_string() }.emit();
        new_value
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use near_sdk::test_utils::{get_logs, VMContextBuilder};
    use near_sdk::testing_env;

    fn as_user(name: &str) {
        let ctx = VMContextBuilder::new().predecessor_account_id(name.parse().unwrap()).build();
        testing_env!(ctx);
    }

    #[test]
    fn increment_decrement_reset() {
        let mut c = Contract::default();
        as_user("alice.testnet");
        c.increment();
        assert_eq!(c.increment(), 2);
        c.decrement();
        c.decrement();
        assert_eq!(c.decrement(), -1);
        assert_eq!(c.reset(), 0);
        assert_eq!(c.get_value("alice.testnet".parse().unwrap()), 0);
    }

    #[test]
    fn counts_each_user_once_and_emits_events() {
        let mut c = Contract::default();
        as_user("alice.testnet");
        c.increment();
        assert!(get_logs()[0].starts_with("EVENT_JSON:"));
        assert!(get_logs()[0].contains("user_registered"));
        c.increment();
        as_user("bob.testnet");
        c.decrement();
        assert_eq!(c.total_users(), 2);
        assert_eq!(c.get_value("bob.testnet".parse().unwrap()), -1);
        assert!(!c.is_user("carol.testnet".parse().unwrap()));
    }
}
