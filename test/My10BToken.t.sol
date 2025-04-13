// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console, console2} from "forge-std/Test.sol";
import {PropertyManagement} from "../src/PropertyManagement.sol";
import {PropertyToken} from "../src/PropertyToken.sol";
import {DeployMy10BToken} from "../script/DeployMy10BToken.s.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AggregatorV3Interface} from "../lib/chainlink-brownie-contracts/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract MockAggregator is AggregatorV3Interface {
    function decimals() external pure override returns (uint8) {
        return 8;
    }

    function description() external pure override returns (string memory) {
        return "Mock Aggregator";
    }

    function version() external pure override returns (uint256) {
        return 1;
    }

    function getRoundData(
        uint80
    )
        external
        pure
        override
        returns (uint80, int256, uint256, uint256, uint80)
    {
        return (0, 2000e8, 0, 0, 0); // price = $2000
    }

    function latestRoundData()
        external
        pure
        override
        returns (uint80, int256, uint256, uint256, uint80)
    {
        return (0, 2000e8, 0, 0, 0); // price = $2000
    }
}

contract My10BToken is ERC20 {
    constructor() ERC20("My10B", "MYB") {
        _mint(msg.sender, 1e24); // 1 million MYB
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract PropertyTestingScript is Test {
    PropertyManagement public propertyManager;
    My10BToken public stableToken;
    MockAggregator public priceFeed;

    address owner = address(this);
    address user = address(0x1);
    uint256 propertyId;

    function setUp() public {
        // Deploy mock price feed & token
        priceFeed = new MockAggregator();
        stableToken = new My10BToken();

        // Deploy PropertyManager
        propertyManager = new PropertyManagement(
            address(priceFeed),
            address(stableToken)
        );

        // Fund PropertyManager with stable token for rewards
        stableToken.mint(address(propertyManager), 100000e18);

        // Label addresses for debug
        vm.label(address(propertyManager), "PropertyManager");
        vm.label(address(stableToken), "StableToken");
        vm.deal(user, 10 ether); // Give user ether for testing
    }

    function testCreateProperty() public {
        propertyManager.createProperty("Gulshan Heights", "one", 10 ether, 12);
        (
            string memory name,
            uint256 totalRaised,
            uint256 maxRaise,
            uint256 duration,
            uint256 lastRewardTime,
            address tokenAddress,
            bool active
        ) = propertyManager.properties(1);

        assertEq(name, "Gulshan Heights");
        assertEq(maxRaise, 10 ether);
    }

    // function testInvest() public {
    //     testCreateProperty();

    //     // User invests 1 ETH
    //     vm.prank(user);
    //     propertyManager.invest{value: 1 ether}(1);

    //     // Correct destructuring: exactly 7 values
    //     (
    //         string memory name,
    //         uint256 totalRaised,
    //         uint256 maxRaise,
    //         uint256 duration,
    //         uint256 lastRewardTime,
    //         address tokenAddress,
    //         bool active
    //     ) = propertyManager.properties(1);

    //     // Interact with the property token
    //     PropertyToken token = PropertyToken(tokenAddress);
    //     uint256 userBalance = token.balanceOf(user);
    //     assertGt(userBalance, 0, "User should receive property tokens");
    // }

    // function testWithdraw() public {
    //     testInvest();

    //     // Destructure the 7 return values, get tokenAddress properly
    //     (, , , , , address tokenAddr, ) = propertyManager.properties(1);

    //     PropertyToken token = PropertyToken(tokenAddr);

    //     vm.startPrank(user);
    //     uint256 balance = token.balanceOf(user);
    //     token.approve(address(propertyManager), balance);
    //     propertyManager.withdraw(1, balance);
    //     vm.stopPrank();

    //     assertEq(
    //         token.balanceOf(user),
    //         0,
    //         "Tokens should be burned after withdrawal"
    //     );
    // }

    // function testDistributeRewards() public {
    //     testInvest();

    //     skip(31 days); // Simulate 1 reward period passed

    //     vm.prank(owner);
    //     propertyManager.distributeRewards();

    //     uint256 reward = propertyManager.accumulatedReward(user);
    //     assertGt(reward, 0, "User should receive rewards");
    // }

    // function testCheckUpkeep() public {
    //     bool upkeep;
    //     bytes memory data;

    //     (upkeep, data) = propertyManager.checkUpkeep("");
    //     assertFalse(upkeep, "Should not need upkeep immediately");

    //     skip(31 days);
    //     (upkeep, data) = propertyManager.checkUpkeep("");
    //     assertTrue(upkeep, "Should need upkeep after reward period");
    // }

    // function testPerformUpkeep() public {
    //     testInvest();
    //     skip(31 days);

    //     propertyManager.performUpkeep("");

    //     uint256 reward = propertyManager.accumulatedReward(user);
    //     assertGt(reward, 0, "Reward should be distributed");
    // }

    // Additional tests for property token creation and dynamic pricing:
    function testPropertyTokenCreation() public {
        propertyManager.createProperty("Test Property", "tsl", 5 ether, 24);
        (
            string memory name,
            uint256 totalRaised,
            uint256 maxRaise,
            uint256 duration,
            uint256 lastRewardTime,
            address tokenAddress,
            bool active
        ) = propertyManager.properties(2);

        PropertyToken token = PropertyToken(tokenAddress);
        uint256 totalSupply = token.totalSupply();
        assertEq(
            totalSupply,
            100000 * 10 ** token.decimals(),
            "Total token supply should be 100,000"
        );
    }

    function testDynamicPriceAdjustment() public {
        testCreateProperty();

        // Fetch the property details after creation to check initial values
        (
            string memory name,
            uint256 totalSupply,
            uint256 totalRaised,
            uint256 duration,
            uint256 lastRewardTime,
            address tokenAddress,
            bool active
        ) = propertyManager.properties(1);

        console2.log(
            "Total Raised: %s, Total Supply: %s",
            totalRaised,
            totalSupply
        );

        // Adjust the calculation to account for decimals in totalSupply
        uint256 expectedInitialPrice = (totalRaised * 1e18) / totalSupply;

        // Get actual token price
        uint256 initialPrice = propertyManager.getTokenPrice(1);

        console2.log(
            "Total expectedInitialPrice: %s, Total initialPrice: %s",
            expectedInitialPrice,
            initialPrice
        );

        // Assert equality
        assertEq(
            initialPrice,
            expectedInitialPrice,
            "Initial price should be calculated correctly based on totalRaised and totalSupply"
        );
    }
}
