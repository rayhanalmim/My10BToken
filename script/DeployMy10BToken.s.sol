// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {My10BToken} from "../src/My10BToken.sol";

contract DeployMy10BToken is Script {
    uint256 public constant initialSupply = 1_000_000 ether;

    function run() external returns (My10BToken) {
        vm.startBroadcast();
        My10BToken my10BToken = new My10BToken(initialSupply);
        vm.stopBroadcast();
        return my10BToken;
    }
}
