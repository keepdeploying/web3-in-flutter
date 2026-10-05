/// Flutter Counter on Sui.
///
/// One shared `Registry` object holds every user's counter in a table, plus
/// the number of users. Move has no signed integers, so each counter is
/// stored as a sign and a magnitude.
module flutter_counter::counter;

use sui::event;
use sui::table::{Self, Table};

const ACTION_INCREMENT: u8 = 0;
const ACTION_DECREMENT: u8 = 1;
const ACTION_RESET: u8 = 2;

/// The shared object every transaction uses.
public struct Registry has key {
    id: UID,
    total_users: u64,
    counters: Table<address, Value>,
}

/// A signed counter value: `negative` plus `magnitude`. Zero is never negative.
public struct Value has copy, drop, store {
    negative: bool,
    magnitude: u64,
}

public struct UserRegistered has copy, drop {
    user: address,
    total_users: u64,
}

public struct CounterChanged has copy, drop {
    user: address,
    old_negative: bool,
    old_magnitude: u64,
    new_negative: bool,
    new_magnitude: u64,
    action: u8,
}

/// Runs once, when the package is published, and shares the registry.
fun init(ctx: &mut TxContext) {
    transfer::share_object(Registry {
        id: object::new(ctx),
        total_users: 0,
        counters: table::new(ctx),
    });
}

public fun increment(registry: &mut Registry, ctx: &TxContext) {
    let old = current(registry, ctx.sender());
    let new = if (old.negative) {
        if (old.magnitude == 1) zero() else Value { negative: true, magnitude: old.magnitude - 1 }
    } else {
        Value { negative: false, magnitude: old.magnitude + 1 }
    };
    set(registry, ctx.sender(), old, new, ACTION_INCREMENT);
}

public fun decrement(registry: &mut Registry, ctx: &TxContext) {
    let old = current(registry, ctx.sender());
    let new = if (old.negative) {
        Value { negative: true, magnitude: old.magnitude + 1 }
    } else if (old.magnitude == 0) {
        Value { negative: true, magnitude: 1 }
    } else {
        Value { negative: false, magnitude: old.magnitude - 1 }
    };
    set(registry, ctx.sender(), old, new, ACTION_DECREMENT);
}

public fun reset(registry: &mut Registry, ctx: &TxContext) {
    let old = current(registry, ctx.sender());
    set(registry, ctx.sender(), old, zero(), ACTION_RESET);
}

/// A user's counter as `(negative, magnitude)`. Users who never called the
/// counter read as zero.
public fun value_of(registry: &Registry, user: address): (bool, u64) {
    let v = current(registry, user);
    (v.negative, v.magnitude)
}

public fun total_users(registry: &Registry): u64 {
    registry.total_users
}

public fun is_user(registry: &Registry, user: address): bool {
    registry.counters.contains(user)
}

fun zero(): Value {
    Value { negative: false, magnitude: 0 }
}

fun current(registry: &Registry, user: address): Value {
    if (registry.counters.contains(user)) *registry.counters.borrow(user) else zero()
}

fun set(registry: &mut Registry, user: address, old: Value, new: Value, action: u8) {
    if (!registry.counters.contains(user)) {
        registry.total_users = registry.total_users + 1;
        registry.counters.add(user, new);
        event::emit(UserRegistered { user, total_users: registry.total_users });
    } else {
        *registry.counters.borrow_mut(user) = new;
    };
    event::emit(CounterChanged {
        user,
        old_negative: old.negative,
        old_magnitude: old.magnitude,
        new_negative: new.negative,
        new_magnitude: new.magnitude,
        action,
    });
}

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(ctx);
}
