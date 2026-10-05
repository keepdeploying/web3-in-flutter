//! Flutter Counter on Solana.
//!
//! Every user gets their own counter account, a PDA derived from
//! `["counter", user]`. A global PDA, `["global"]`, tracks how many users have
//! ever used the program. Both are created on a user's first call, so the app
//! needs only one instruction per action.
use anchor_lang::prelude::*;

declare_id!("B5FWXqM3hrna9SCPp2r2APzEmaMzash3N6t9kkwpD5qH");

pub const GLOBAL_SEED: &[u8] = b"global";
pub const COUNTER_SEED: &[u8] = b"counter";

#[program]
pub mod flutter_counter {
    use super::*;

    pub fn increment(ctx: Context<Update>) -> Result<()> {
        let new_value = ctx.accounts.counter.value.checked_add(1).ok_or(CounterError::Overflow)?;
        apply(ctx, new_value, Action::Increment)
    }

    pub fn decrement(ctx: Context<Update>) -> Result<()> {
        let new_value = ctx.accounts.counter.value.checked_sub(1).ok_or(CounterError::Overflow)?;
        apply(ctx, new_value, Action::Decrement)
    }

    pub fn reset(ctx: Context<Update>) -> Result<()> {
        apply(ctx, 0, Action::Reset)
    }
}

fn apply(ctx: Context<Update>, new_value: i64, action: Action) -> Result<()> {
    let user = ctx.accounts.user.key();
    let counter = &mut ctx.accounts.counter;
    let global = &mut ctx.accounts.global;

    // A freshly created counter account has no owner recorded yet.
    if counter.user == Pubkey::default() {
        counter.user = user;
        counter.bump = ctx.bumps.counter;
        global.total_users = global.total_users.checked_add(1).ok_or(CounterError::Overflow)?;
        emit!(UserRegistered { user, total_users: global.total_users });
    }

    let old_value = counter.value;
    counter.value = new_value;
    emit!(CounterChanged { user, old_value, new_value, action });
    Ok(())
}

#[derive(Accounts)]
pub struct Update<'info> {
    #[account(
        init_if_needed,
        payer = user,
        space = 8 + Global::INIT_SPACE,
        seeds = [GLOBAL_SEED],
        bump
    )]
    pub global: Account<'info, Global>,

    #[account(
        init_if_needed,
        payer = user,
        space = 8 + Counter::INIT_SPACE,
        seeds = [COUNTER_SEED, user.key().as_ref()],
        bump
    )]
    pub counter: Account<'info, Counter>,

    #[account(mut)]
    pub user: Signer<'info>,

    pub system_program: Program<'info, System>,
}

#[account]
#[derive(InitSpace)]
pub struct Global {
    pub total_users: u64,
}

#[account]
#[derive(InitSpace)]
pub struct Counter {
    pub user: Pubkey,
    pub value: i64,
    pub bump: u8,
}

#[derive(AnchorSerialize, AnchorDeserialize, Clone, Copy, PartialEq, Eq, Debug)]
pub enum Action {
    Increment,
    Decrement,
    Reset,
}

#[event]
pub struct UserRegistered {
    pub user: Pubkey,
    pub total_users: u64,
}

#[event]
pub struct CounterChanged {
    pub user: Pubkey,
    pub old_value: i64,
    pub new_value: i64,
    pub action: Action,
}

#[error_code]
pub enum CounterError {
    #[msg("The counter went past the range of a 64-bit integer")]
    Overflow,
}
