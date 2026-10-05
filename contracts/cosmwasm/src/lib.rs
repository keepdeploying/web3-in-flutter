//! Flutter Counter on CosmWasm.
//!
//! Each user (the message sender) has their own counter. The contract also
//! counts how many users have ever used it.
use cosmwasm_schema::{cw_serde, QueryResponses};
use cosmwasm_std::{
    entry_point, to_json_binary, Addr, Binary, Deps, DepsMut, Env, MessageInfo, Response,
    StdResult,
};
use cw_storage_plus::{Item, Map};

pub const TOTAL_USERS: Item<u64> = Item::new("total_users");
pub const COUNTERS: Map<&Addr, i64> = Map::new("counters");

#[cw_serde]
pub struct InstantiateMsg {}

#[cw_serde]
pub enum ExecuteMsg {
    Increment {},
    Decrement {},
    Reset {},
}

#[cw_serde]
#[derive(QueryResponses)]
pub enum QueryMsg {
    /// A user's counter. Users who never called the contract read as 0.
    #[returns(ValueResponse)]
    Value { user: String },
    #[returns(TotalUsersResponse)]
    TotalUsers {},
}

#[cw_serde]
pub struct ValueResponse {
    pub value: i64,
    pub is_user: bool,
}

#[cw_serde]
pub struct TotalUsersResponse {
    pub total_users: u64,
}

#[derive(thiserror::Error, Debug, PartialEq)]
pub enum ContractError {
    #[error(transparent)]
    Std(#[from] cosmwasm_std::StdError),
    #[error("the counter went past the range of a 64-bit integer")]
    Overflow,
}

#[cfg_attr(not(feature = "library"), entry_point)]
pub fn instantiate(deps: DepsMut, _env: Env, _info: MessageInfo, _msg: InstantiateMsg) -> StdResult<Response> {
    TOTAL_USERS.save(deps.storage, &0)?;
    Ok(Response::new().add_attribute("action", "instantiate"))
}

#[cfg_attr(not(feature = "library"), entry_point)]
pub fn execute(deps: DepsMut, _env: Env, info: MessageInfo, msg: ExecuteMsg) -> Result<Response, ContractError> {
    let user = info.sender;
    let existing = COUNTERS.may_load(deps.storage, &user)?;
    let old = existing.unwrap_or(0);
    let (new, action) = match msg {
        ExecuteMsg::Increment {} => (old.checked_add(1).ok_or(ContractError::Overflow)?, "increment"),
        ExecuteMsg::Decrement {} => (old.checked_sub(1).ok_or(ContractError::Overflow)?, "decrement"),
        ExecuteMsg::Reset {} => (0, "reset"),
    };

    let mut response = Response::new();
    if existing.is_none() {
        let total = TOTAL_USERS.load(deps.storage)? + 1;
        TOTAL_USERS.save(deps.storage, &total)?;
        response = response.add_event(
            cosmwasm_std::Event::new("user_registered")
                .add_attribute("user", user.as_str())
                .add_attribute("total_users", total.to_string()),
        );
    }
    COUNTERS.save(deps.storage, &user, &new)?;

    Ok(response.add_event(
        cosmwasm_std::Event::new("counter_changed")
            .add_attribute("user", user.as_str())
            .add_attribute("old_value", old.to_string())
            .add_attribute("new_value", new.to_string())
            .add_attribute("action", action),
    ))
}

#[cfg_attr(not(feature = "library"), entry_point)]
pub fn query(deps: Deps, _env: Env, msg: QueryMsg) -> StdResult<Binary> {
    match msg {
        QueryMsg::Value { user } => {
            let addr = deps.api.addr_validate(&user)?;
            let value = COUNTERS.may_load(deps.storage, &addr)?;
            to_json_binary(&ValueResponse { value: value.unwrap_or(0), is_user: value.is_some() })
        }
        QueryMsg::TotalUsers {} => to_json_binary(&TotalUsersResponse { total_users: TOTAL_USERS.load(deps.storage)? }),
    }
}
