// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/Test.sol";

import {My10BToken} from "../src/My10BToken.sol";
import {PropertyManagement} from "../src/PropertyManagement.sol";
import {TraditionalInvestmentManager} from "../src/TraditionalInvestmentManager.sol";
import {PropertyManagementView} from "../src/PropertyManagementView.sol";

contract DeployAll is Script {
    uint256 public constant initialSupply = 1_000_000 ether;

    function run()
        external
        returns (
            address my10BTokenAddr,
            address propertyManagerAddr,
            address traditionalManagerAddr,
            address propertyViewAddr
        )
    {
        address priceFeed = vm.envAddress("CHAINLINK_PRICE_FEED"); 

        vm.startBroadcast();

        // 1️⃣ Deploy your ERC20 token
        My10BToken my10BToken = new My10BToken(initialSupply);
        my10BTokenAddr = address(my10BToken);


        // 3️⃣ Deploy PropertyManagement with dummy TraditionalInvestmentManager address
        PropertyManagement propertyManager = new PropertyManagement(
            priceFeed,
            my10BTokenAddr
        );
        propertyManagerAddr = address(propertyManager);

        // 4️⃣ Now deploy real TraditionalInvestmentManager with correct propertyManager address
        TraditionalInvestmentManager traditionalManager = new TraditionalInvestmentManager(
                propertyManagerAddr,
                my10BTokenAddr
            );
        traditionalManagerAddr = address(traditionalManager);

        // 5️⃣ IMPORTANT: Set the correct TraditionalManager inside PropertyManagement
        // You can do this by re-setting from frontend later, or if you want,
        // add a setter function like `setTraditionalManager(address)` inside PropertyManagement.
        // (I can show you if you want.)

        // 6️⃣ Deploy View contract
        PropertyManagementView propertyView = new PropertyManagementView(
            propertyManagerAddr
        );
        propertyViewAddr = address(propertyView);

        vm.stopBroadcast();

        console2.log(" My10BToken deployed at:        ", my10BTokenAddr);
        console2.log("PropertyManagement deployed at:", propertyManagerAddr);
        console2.log(
            " TraditionalInvestmentManager:  ",
            traditionalManagerAddr
        );
        console2.log(" PropertyManagementView:        ", propertyViewAddr);
    }
}
