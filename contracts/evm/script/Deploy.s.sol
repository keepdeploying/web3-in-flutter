// SPDX-License-Identifier: MIT
pragma solidity ^0.8.37;

import {Script, console} from "forge-std/src/Script.sol";
import {FlutterCounter} from "../src/FlutterCounter.sol";

/// @notice Deploys FlutterCounter with CREATE2 through the standard
/// deterministic deployer (0x4e59b44847b379578588920cA78FbF26c0B4956C), which
/// exists on every network we use. Same bytecode + same salt = same address
/// on every network.
contract Deploy is Script {
    bytes32 constant SALT = keccak256("web3-in-flutter.FlutterCounter.v1");

    function run() external returns (FlutterCounter counter) {
        address predicted =
            vm.computeCreate2Address(SALT, keccak256(type(FlutterCounter).creationCode), CREATE2_FACTORY);
        console.log("Predicted address:", predicted);

        if (predicted.code.length > 0) {
            console.log("Already deployed on this network. Nothing to do.");
            return FlutterCounter(predicted);
        }

        // Call the deterministic deployer directly. Its input is the salt
        // followed by the contract's creation code, and it returns the new
        // contract's address. (`new FlutterCounter{salt: SALT}()` relies on
        // Foundry routing the call through the deployer, which it doesn't do
        // on every network.)
        vm.startBroadcast();
        (bool ok, bytes memory result) = CREATE2_FACTORY.call(abi.encodePacked(SALT, type(FlutterCounter).creationCode));
        vm.stopBroadcast();

        require(ok, "deterministic deployer call failed");
        counter = FlutterCounter(address(bytes20(result)));
        require(address(counter) == predicted, "unexpected address");
        console.log("Deployed FlutterCounter at:", address(counter));
    }
}
