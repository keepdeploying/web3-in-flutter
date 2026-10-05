#[test_only]
module flutter_counter::counter_tests;

use flutter_counter::counter::{Self, Registry};
use sui::test_scenario as ts;

const ALICE: address = @0xA11CE;
const BOB: address = @0xB0B;

#[test]
fun increment_decrement_reset() {
    let mut s = ts::begin(ALICE);
    counter::init_for_testing(s.ctx());
    s.next_tx(ALICE);
    {
        let mut r = s.take_shared<Registry>();
        counter::increment(&mut r, s.ctx());
        counter::increment(&mut r, s.ctx());
        assert_value(&r, ALICE, false, 2);
        counter::decrement(&mut r, s.ctx());
        counter::decrement(&mut r, s.ctx());
        counter::decrement(&mut r, s.ctx());
        assert_value(&r, ALICE, true, 1);
        counter::decrement(&mut r, s.ctx());
        assert_value(&r, ALICE, true, 2);
        counter::increment(&mut r, s.ctx());
        counter::increment(&mut r, s.ctx());
        assert_value(&r, ALICE, false, 0);
        counter::decrement(&mut r, s.ctx());
        counter::reset(&mut r, s.ctx());
        assert_value(&r, ALICE, false, 0);
        ts::return_shared(r);
    };
    s.end();
}

#[test]
fun counts_each_user_once() {
    let mut s = ts::begin(ALICE);
    counter::init_for_testing(s.ctx());
    s.next_tx(ALICE);
    {
        let mut r = s.take_shared<Registry>();
        counter::increment(&mut r, s.ctx());
        counter::increment(&mut r, s.ctx());
        ts::return_shared(r);
    };
    s.next_tx(BOB);
    {
        let mut r = s.take_shared<Registry>();
        counter::decrement(&mut r, s.ctx());
        assert!(counter::total_users(&r) == 2);
        assert_value(&r, ALICE, false, 2);
        assert_value(&r, BOB, true, 1);
        assert!(!counter::is_user(&r, @0xC0FFEE));
        ts::return_shared(r);
    };
    s.end();
}

fun assert_value(r: &Registry, user: address, negative: bool, magnitude: u64) {
    let (n, m) = counter::value_of(r, user);
    assert!(n == negative);
    assert!(m == magnitude);
}
