use cosmwasm_std::Addr;
use cw_multi_test::{App, ContractWrapper, Executor, IntoBech32};
use flutter_counter::{execute, instantiate, query, ExecuteMsg, InstantiateMsg, QueryMsg, TotalUsersResponse, ValueResponse};

fn setup() -> (App, Addr) {
    let mut app = App::default();
    let code = app.store_code(Box::new(ContractWrapper::new(execute, instantiate, query)));
    let owner = "owner".into_bech32();
    let contract = app
        .instantiate_contract(code, owner, &InstantiateMsg {}, &[], "flutter-counter", None)
        .unwrap();
    (app, contract)
}

fn value(app: &App, contract: &Addr, user: &Addr) -> ValueResponse {
    app.wrap().query_wasm_smart(contract, &QueryMsg::Value { user: user.to_string() }).unwrap()
}

#[test]
fn increment_decrement_reset() {
    let (mut app, contract) = setup();
    let alice = "alice".into_bech32();
    for msg in [ExecuteMsg::Increment {}, ExecuteMsg::Increment {}] {
        app.execute_contract(alice.clone(), contract.clone(), &msg, &[]).unwrap();
    }
    assert_eq!(value(&app, &contract, &alice).value, 2);
    for _ in 0..3 {
        app.execute_contract(alice.clone(), contract.clone(), &ExecuteMsg::Decrement {}, &[]).unwrap();
    }
    assert_eq!(value(&app, &contract, &alice).value, -1);
    app.execute_contract(alice.clone(), contract.clone(), &ExecuteMsg::Reset {}, &[]).unwrap();
    assert_eq!(value(&app, &contract, &alice), ValueResponse { value: 0, is_user: true });
}

#[test]
fn counts_each_user_once() {
    let (mut app, contract) = setup();
    let alice = "alice".into_bech32();
    let bob = "bob".into_bech32();
    app.execute_contract(alice.clone(), contract.clone(), &ExecuteMsg::Increment {}, &[]).unwrap();
    app.execute_contract(alice.clone(), contract.clone(), &ExecuteMsg::Increment {}, &[]).unwrap();
    app.execute_contract(bob.clone(), contract.clone(), &ExecuteMsg::Decrement {}, &[]).unwrap();
    let total: TotalUsersResponse = app.wrap().query_wasm_smart(&contract, &QueryMsg::TotalUsers {}).unwrap();
    assert_eq!(total.total_users, 2);
    assert_eq!(value(&app, &contract, &bob).value, -1);
    assert!(!value(&app, &contract, &"carol".into_bech32()).is_user);
}
