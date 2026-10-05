// SPDX-License-Identifier: MIT
pragma solidity ^0.8.37;

/// @title FlutterCounter
/// @notice Every user gets their own counter. A user is registered on their
/// first call, which also bumps `totalUsers`.
contract FlutterCounter {
    /// @notice Number of distinct users who have ever called the counter.
    uint256 public totalUsers;

    /// @notice Each user's current counter value.
    mapping(address user => int256 value) public counterOf;

    /// @notice Whether a user has called the counter before.
    mapping(address user => bool registered) public isUser;

    event UserRegistered(address indexed user, uint256 totalUsers);
    event CounterChanged(address indexed user, int256 oldValue, int256 newValue, Action action);

    enum Action {
        Increment,
        Decrement,
        Reset
    }

    function increment() external {
        _set(counterOf[msg.sender] + 1, Action.Increment);
    }

    function decrement() external {
        _set(counterOf[msg.sender] - 1, Action.Decrement);
    }

    function reset() external {
        _set(0, Action.Reset);
    }

    function _set(int256 newValue, Action action) private {
        if (!isUser[msg.sender]) {
            isUser[msg.sender] = true;
            totalUsers += 1;
            emit UserRegistered(msg.sender, totalUsers);
        }
        int256 oldValue = counterOf[msg.sender];
        counterOf[msg.sender] = newValue;
        emit CounterChanged(msg.sender, oldValue, newValue, action);
    }
}
