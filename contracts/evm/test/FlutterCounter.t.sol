// SPDX-License-Identifier: MIT
pragma solidity ^0.8.37;

import {Test} from "forge-std/src/Test.sol";
import {FlutterCounter} from "../src/FlutterCounter.sol";

contract FlutterCounterTest is Test {
    FlutterCounter counter;
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    function setUp() public {
        counter = new FlutterCounter();
    }

    function test_IncrementDecrementReset() public {
        vm.startPrank(alice);
        counter.increment();
        counter.increment();
        assertEq(counter.counterOf(alice), 2);
        counter.decrement();
        counter.decrement();
        counter.decrement();
        assertEq(counter.counterOf(alice), -1);
        counter.reset();
        assertEq(counter.counterOf(alice), 0);
        vm.stopPrank();
    }

    function test_CountersAreSeparatePerUser() public {
        vm.prank(alice);
        counter.increment();
        vm.prank(bob);
        counter.decrement();
        assertEq(counter.counterOf(alice), 1);
        assertEq(counter.counterOf(bob), -1);
    }

    function test_TotalUsersCountsEachUserOnce() public {
        vm.startPrank(alice);
        counter.increment();
        counter.increment();
        vm.stopPrank();
        vm.prank(bob);
        counter.reset();
        assertEq(counter.totalUsers(), 2);
        assertTrue(counter.isUser(alice));
    }

    function test_EmitsEvents() public {
        vm.expectEmit(true, false, false, true);
        emit FlutterCounter.UserRegistered(alice, 1);
        vm.expectEmit(true, false, false, true);
        emit FlutterCounter.CounterChanged(alice, 0, 1, FlutterCounter.Action.Increment);
        vm.prank(alice);
        counter.increment();
    }
}
