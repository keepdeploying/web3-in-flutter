// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from 'forge-std/Script.sol';
import {FlutterCounter} from '../src/FlutterCounter.sol';

contract CounterScript is Script {
  FlutterCounter public counter;

  function setUp() public {}

  function run() public {
    vm.startBroadcast();
    counter = new FlutterCounter();
    vm.stopBroadcast();
  }
}
