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

        vm.startBroadcast();
        counter = new FlutterCounter{salt: SALT}();
        vm.stopBroadcast();

        require(address(counter) == predicted, "unexpected address");
        console.log("Deployed FlutterCounter at:", address(counter));
    }
}
