//! Runs the compiled program in LiteSVM, an in-process Solana runtime.
//! Build first with `anchor build`, then run `cargo test`.
use {
    anchor_lang::{
        prelude::Pubkey, solana_program::instruction::Instruction, solana_program::system_program,
        AccountDeserialize, InstructionData, ToAccountMetas,
    },
    flutter_counter::{Counter, Global, COUNTER_SEED, GLOBAL_SEED},
    litesvm::LiteSVM,
    solana_keypair::Keypair,
    solana_message::{Message, VersionedMessage},
    solana_signer::Signer,
    solana_transaction::versioned::VersionedTransaction,
};

fn setup() -> LiteSVM {
    let mut svm = LiteSVM::new();
    let bytes = include_bytes!(concat!(env!("CARGO_TARGET_TMPDIR"), "/../deploy/flutter_counter.so"));
    svm.add_program(flutter_counter::id(), bytes).unwrap();
    svm
}

fn user(svm: &mut LiteSVM) -> Keypair {
    let kp = Keypair::new();
    svm.airdrop(&kp.pubkey(), 1_000_000_000).unwrap();
    kp
}

fn pdas(user: &Pubkey) -> (Pubkey, Pubkey) {
    let id = flutter_counter::id();
    let global = Pubkey::find_program_address(&[GLOBAL_SEED], &id).0;
    let counter = Pubkey::find_program_address(&[COUNTER_SEED, user.as_ref()], &id).0;
    (global, counter)
}

fn send(svm: &mut LiteSVM, signer: &Keypair, data: Vec<u8>) {
    let (global, counter) = pdas(&signer.pubkey());
    let ix = Instruction::new_with_bytes(
        flutter_counter::id(),
        &data,
        flutter_counter::accounts::Update {
            global,
            counter,
            user: signer.pubkey(),
            system_program: system_program::ID,
        }
        .to_account_metas(None),
    );
    let msg = Message::new_with_blockhash(&[ix], Some(&signer.pubkey()), &svm.latest_blockhash());
    let tx = VersionedTransaction::try_new(VersionedMessage::Legacy(msg), &[signer]).unwrap();
    svm.send_transaction(tx).expect("transaction failed");
    svm.expire_blockhash();
}

fn value(svm: &LiteSVM, user: &Pubkey) -> i64 {
    let acc = svm.get_account(&pdas(user).1).unwrap();
    Counter::try_deserialize(&mut acc.data.as_slice()).unwrap().value
}

fn total_users(svm: &LiteSVM) -> u64 {
    let acc = svm.get_account(&pdas(&Pubkey::default()).0).unwrap();
    Global::try_deserialize(&mut acc.data.as_slice()).unwrap().total_users
}

#[test]
fn increment_decrement_reset() {
    let mut svm = setup();
    let alice = user(&mut svm);
    send(&mut svm, &alice, flutter_counter::instruction::Increment {}.data());
    send(&mut svm, &alice, flutter_counter::instruction::Increment {}.data());
    assert_eq!(value(&svm, &alice.pubkey()), 2);
    send(&mut svm, &alice, flutter_counter::instruction::Decrement {}.data());
    send(&mut svm, &alice, flutter_counter::instruction::Decrement {}.data());
    send(&mut svm, &alice, flutter_counter::instruction::Decrement {}.data());
    assert_eq!(value(&svm, &alice.pubkey()), -1);
    send(&mut svm, &alice, flutter_counter::instruction::Reset {}.data());
    assert_eq!(value(&svm, &alice.pubkey()), 0);
}

#[test]
fn counters_are_per_user_and_users_counted_once() {
    let mut svm = setup();
    let alice = user(&mut svm);
    let bob = user(&mut svm);
    send(&mut svm, &alice, flutter_counter::instruction::Increment {}.data());
    send(&mut svm, &alice, flutter_counter::instruction::Increment {}.data());
    send(&mut svm, &bob, flutter_counter::instruction::Decrement {}.data());
    assert_eq!(value(&svm, &alice.pubkey()), 2);
    assert_eq!(value(&svm, &bob.pubkey()), -1);
    assert_eq!(total_users(&svm), 2);
}
