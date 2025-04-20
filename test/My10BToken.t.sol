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
            uint256 totalSupply,
            uint256 totalRaised,
            uint256 annualRewardRate,
            uint256 investedAmount,
            address tokenAddress,
            bool active
        ) = propertyManager.properties(1);

        assertEq(name, "Gulshan Heights");
        assertEq(totalRaised, 10 ether);
        assertEq(totalSupply, 100000 * 1e18);
        assertEq(annualRewardRate, 12);
        assertTrue(active);
    }

    function testInvest() public {
        testCreateProperty();

        // Mint and approve tokens to the user
        stableToken.mint(user, 1 ether);

        vm.startPrank(user);
        stableToken.approve(address(propertyManager), 1 ether);
        propertyManager.invest(1, 1 ether);
        vm.stopPrank();

        (, , , , , address tokenAddress, ) = propertyManager.properties(1);
        PropertyToken token = PropertyToken(tokenAddress);
        uint256 userBalance = token.balanceOf(user);

        assertGt(userBalance, 0, "User should receive property tokens");
    }

    function testDistributeRewards() public {
        testInvest();
        skip(31 days);

        vm.prank(owner);
        propertyManager.distributeRewards();

        uint256 reward = propertyManager.accumulatedReward(user);
        assertGt(reward, 0, "User should receive rewards");
    }

    function testTraditionalInvestmentAndClaim() public {
        propertyManager.createProperty("Banani View", "BNV", 10 ether, 15);

        string memory secret = "mySecret";
        bytes32 hashed = keccak256(abi.encodePacked(secret));

        vm.prank(owner);
        propertyManager.addTraditionalInvestment(user, 1, secret, 5 ether);

        skip(2 days);

        vm.startPrank(user);
        propertyManager.claimTokensBySecret(secret);
        vm.stopPrank();

        assertEq(
            stableToken.balanceOf(user),
            5 ether,
            "User should receive claimed amount"
        );
        assertTrue(
            propertyManager.hasClaimedTokens(user, hashed),
            "Claim flag should be true"
        );
    }

    function testWalletToWalletTransferTracking() public {
        testInvest(); // Makes user 0x1 invest

        (, , , , , address tokenAddress, ) = propertyManager.properties(1);
        PropertyToken token = PropertyToken(tokenAddress);

        address receiver = address(0x2);
        vm.deal(receiver, 1 ether);

        vm.startPrank(user);
        token.transfer(receiver, token.balanceOf(user) / 2);
        vm.stopPrank();

        uint256 userInv = propertyManager.userInvestments(user, 1);
        uint256 receiverInv = propertyManager.userInvestments(receiver, 1);

        assertGt(
            receiverInv,
            0,
            "Receiver should have investment value updated"
        );
        assertLt(userInv, 1 ether, "User's investment should be reduced");
    }

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

    function testCannotReenterClaim() public {
        propertyManager.createProperty("Test", "TST", 10 ether, 10);

        string memory secret = "haxor";
        vm.prank(owner);
        propertyManager.addTraditionalInvestment(user, 1, secret, 5 ether);

        skip(2 days);

        vm.prank(user);
        propertyManager.claimTokensBySecret(secret);

        // Try re-entering again with same secret
        vm.expectRevert("Tokens already claimed");
        vm.prank(user);
        propertyManager.claimTokensBySecret(secret);
    }

    function testHoldStartTimeUpdateOnTransfer() public {
        testInvest();

        (, , , , , address tokenAddress, ) = propertyManager.properties(1);
        PropertyToken token = PropertyToken(tokenAddress);

        address receiver = address(0x2);
        vm.deal(receiver, 1 ether);

        // Fast forward to simulate holding
        skip(10 days);

        uint256 amountToSend;
        vm.startPrank(user);
        amountToSend = token.balanceOf(user) / 2;
        token.transfer(receiver, amountToSend);
        vm.stopPrank();

        uint256 holdTimeReceiver = propertyManager.holdStartTime(receiver, 1);
        uint256 holdTimeSender = propertyManager.holdStartTime(user, 1);

        assertGt(holdTimeReceiver, 0, "Receiver hold time should be set");
        assertLt(
            holdTimeSender,
            block.timestamp,
            "Sender's hold time should not reset"
        );
    }

    function testTransferMoreThanBalanceFails() public {
        testInvest();
        (, , , , , address tokenAddress, ) = propertyManager.properties(1);
        PropertyToken token = PropertyToken(tokenAddress);

        vm.startPrank(user);
        vm.expectRevert(); // ERC20 should revert
        token.transfer(address(0x3), token.balanceOf(user) + 1);
        vm.stopPrank();
    }
}
