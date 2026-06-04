use anchor_lang::prelude::*;

declare_id!("D3YxtKxZS6iNCHbVEZjAXqTzyskUz2RjQJuJ5Wo3t1D");

#[program]
pub mod flutter_counter {
    use super::*;

    pub fn initialize_global(ctx: Context<InitializeGlobal>) -> Result<()> {
        let global_state = &mut ctx.accounts.global_state;
        global_state.authority = ctx.accounts.authority.key();
        global_state.total_users = 0;

        emit!(GlobalStateInitialized {
            authority: ctx.accounts.authority.key(),
        });

        Ok(())
    }

    pub fn initialize_user_counter(ctx: Context<InitializeUserCounter>) -> Result<()> {
        let user_counter = &mut ctx.accounts.user_counter;
        let global_state = &mut ctx.accounts.global_state;

        user_counter.owner = ctx.accounts.user.key();
        user_counter.value = 0;

        // Increment total users count
        global_state.total_users += 1;

        emit!(UserCounterInitialized {
            user: ctx.accounts.user.key(),
            initial_value: 0,
            total_users: global_state.total_users,
        });

        Ok(())
    }

    pub fn increment(ctx: Context<ModifyUserCounter>) -> Result<()> {
        let user_counter = &mut ctx.accounts.user_counter;
        let old_value = user_counter.value;
        user_counter.value += 1;

        emit!(CounterIncremented {
            user: ctx.accounts.user.key(),
            old_value,
            new_value: user_counter.value,
        });

        Ok(())
    }

    pub fn decrement(ctx: Context<ModifyUserCounter>) -> Result<()> {
        let user_counter = &mut ctx.accounts.user_counter;
        let old_value = user_counter.value;
        user_counter.value -= 1;

        emit!(CounterDecremented {
            user: ctx.accounts.user.key(),
            old_value,
            new_value: user_counter.value,
        });

        Ok(())
    }

    pub fn reset(ctx: Context<ModifyUserCounter>) -> Result<()> {
        let user_counter = &mut ctx.accounts.user_counter;
        let old_value = user_counter.value;
        user_counter.value = 0;

        emit!(CounterReset {
            user: ctx.accounts.user.key(),
            old_value,
        });

        Ok(())
    }
}

#[derive(Accounts)]
pub struct InitializeGlobal<'info> {
    #[account(
        init,
        payer = authority,
        space = 8 + 32 + 8, // discriminator + authority + total_users
        seeds = [b"global_state"],
        bump
    )]
    pub global_state: Account<'info, GlobalState>,

    #[account(mut)]
    pub authority: Signer<'info>,

    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct InitializeUserCounter<'info> {
    #[account(
        init,
        payer = user,
        space = 8 + 32 + 8, // discriminator + owner + value
        seeds = [b"user_counter", user.key().as_ref()],
        bump
    )]
    pub user_counter: Account<'info, UserCounter>,

    #[account(
        mut,
        seeds = [b"global_state"],
        bump
    )]
    pub global_state: Account<'info, GlobalState>,

    #[account(mut)]
    pub user: Signer<'info>,

    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct ModifyUserCounter<'info> {
    #[account(
        mut,
        seeds = [b"user_counter", user.key().as_ref()],
        bump,
        constraint = user_counter.owner == user.key() @ CounterError::Unauthorized
    )]
    pub user_counter: Account<'info, UserCounter>,

    #[account(mut)]
    pub user: Signer<'info>,
}

#[derive(Accounts)]
pub struct GetUserCounter<'info> {
    #[account(
        seeds = [b"user_counter", user_counter.owner.as_ref()],
        bump
    )]
    pub user_counter: Account<'info, UserCounter>,
}

#[derive(Accounts)]
pub struct GetTotalUsers<'info> {
    #[account(
        seeds = [b"global_state"],
        bump
    )]
    pub global_state: Account<'info, GlobalState>,
}

#[account]
pub struct GlobalState {
    pub authority: Pubkey,
    pub total_users: u64,
}

#[account]
pub struct UserCounter {
    pub owner: Pubkey,
    pub value: i64,
}

// Separate event types for each state change
#[event]
pub struct GlobalStateInitialized {
    pub authority: Pubkey,
}

#[event]
pub struct UserCounterInitialized {
    pub user: Pubkey,
    pub initial_value: i64,
    pub total_users: u64,
}

#[event]
pub struct CounterIncremented {
    pub user: Pubkey,
    pub old_value: i64,
    pub new_value: i64,
}

#[event]
pub struct CounterDecremented {
    pub user: Pubkey,
    pub old_value: i64,
    pub new_value: i64,
}

#[event]
pub struct CounterReset {
    pub user: Pubkey,
    pub old_value: i64,
}

#[error_code]
pub enum CounterError {
    #[msg("Unauthorized access")]
    Unauthorized,
}
