// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

contract FlutterCounter {
  address public owner;
  uint256 public totalUsers;
  mapping(address => int256) public userCounters;
  mapping(address => bool) public userExists;

  event NewUserCounter(address indexed user, uint256 totalUsers);
  event CounterIncremented(address indexed user, int256 oldValue, int256 newValue);
  event CounterDecremented(address indexed user, int256 oldValue, int256 newValue);
  event CounterReset(address indexed user, int256 oldValue);

  constructor() {
    owner = msg.sender;
  }

  function _initializeUserIfNeeded() private {
    if (!userExists[msg.sender]) {
      userExists[msg.sender] = true;
      totalUsers += 1;
      emit NewUserCounter(msg.sender, totalUsers);
    }
  }

  function increment() external {
    _initializeUserIfNeeded();
    int256 oldValue = userCounters[msg.sender];
    userCounters[msg.sender] += 1;
    emit CounterIncremented(msg.sender, oldValue, oldValue + 1);
  }

  function decrement() external {
    _initializeUserIfNeeded();
    int256 oldValue = userCounters[msg.sender];
    userCounters[msg.sender] -= 1;
    emit CounterDecremented(msg.sender, oldValue, oldValue - 1);
  }

  function reset() external {
    _initializeUserIfNeeded();
    int256 oldValue = userCounters[msg.sender];
    userCounters[msg.sender] = 0;
    emit CounterReset(msg.sender, oldValue);
  }
}
