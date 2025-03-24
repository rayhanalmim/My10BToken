// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {KeeperCompatibleInterface} from "../lib/chainlink-brownie-contracts/contracts/src/v0.8/automation/interfaces/KeeperCompatibleInterface.sol";
import {AggregatorV3Interface} from "../lib/chainlink-brownie-contracts/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {PropertyToken} from "./PropertyToken.sol";

contract PropertyManagement is Ownable, KeeperCompatibleInterface, Pausable {
    using SafeERC20 for ERC20;

    struct Property {
        string name;
        uint256 totalSupply;
        uint256 totalRaised;
        uint256 annualRewardRate;
        uint256 investedAmount;
        address propertyToken;
        bool active;
    }

    uint256 public constant MIN_HOLD_TIME = 1 days;
    uint256 public constant REWARD_DISTRIBUTION_PERIOD = 30 days;
    uint256 public constant TOTAL_PROPERTY_TOKENS = 1000000;
    uint256 public lastRewardDistribution;

    address[] public investors;
    mapping(address => bool) public isInvestor;
    mapping(uint256 => Property) public properties;
    mapping(address => mapping(uint256 => uint256)) public userInvestments;
    mapping(address => mapping(uint256 => uint256)) public holdStartTime;
    mapping(address => uint256) public accumulatedReward;

    AggregatorV3Interface internal priceFeed;
    uint256 public propertyCounter;

    address public tokenAddress;

    event PropertyCreated(
        uint256 indexed propertyId,
        string name,
        uint256 totalSupply,
        uint256 totalRaised,
        uint256 annualRewardRate,
        address propertyToken
    );

    event Invested(
        address indexed user,
        uint256 propertyId,
        uint256 amount,
        uint256 tokensReceived
    );
    event Withdrawn(
        address indexed user,
        uint256 propertyId,
        uint256 amount,
        uint256 tokensBurned
    );
    event RewardDistributed(address indexed user, uint256 amount);

    constructor(address _priceFeed, address _tokenAddress) Ownable(msg.sender) {
        priceFeed = AggregatorV3Interface(_priceFeed);
        tokenAddress = _tokenAddress;
        lastRewardDistribution = block.timestamp;
    }

    function createProperty(
        string memory _name,
        uint256 _totalSupply,
        uint256 _totalRaised,
        uint256 _annualRewardRate
    ) external onlyOwner {
        require(_annualRewardRate > 0, "Annual reward rate must be positive");
        require(_totalRaised > 0, "Total raised amount must be positive");

        PropertyToken newToken = new PropertyToken(
            _name,
            _name,
            msg.sender,
            TOTAL_PROPERTY_TOKENS
        );

        propertyCounter++;
        properties[propertyCounter] = Property({
            name: _name,
            totalSupply: _totalSupply,
            totalRaised: _totalRaised,
            annualRewardRate: _annualRewardRate,
            investedAmount: 0,
            propertyToken: address(newToken),
            active: true
        });

        emit PropertyCreated(
            propertyCounter,
            _name,
            _totalSupply,
            _totalRaised,
            _annualRewardRate,
            address(newToken)
        );
    }

    function getTokenPrice(uint256 _propertyId) public view returns (uint256) {
        Property storage property = properties[_propertyId];
        require(property.totalSupply > 0, "Invalid property supply");
        return property.totalRaised / property.totalSupply;
    }

    function invest(uint256 _propertyId) external payable whenNotPaused {
        Property storage property = properties[_propertyId];
        require(property.active, "Property is not active");
        require(property.totalRaised > 0, "Total raised must be set");
        require(msg.value > 0, "Investment amount must be greater than zero");

        uint256 propertyTokens = (msg.value * 100000) / property.totalRaised;
        require(propertyTokens > 0, "Investment too low for tokens");

        uint256 contractTokenBalance = PropertyToken(property.propertyToken)
            .balanceOf(address(this));
        require(
            contractTokenBalance >= propertyTokens,
            "Not enough tokens available for distribution"
        );

        property.investedAmount += msg.value;
        userInvestments[msg.sender][_propertyId] += msg.value;

        PropertyToken(property.propertyToken).transfer(
            msg.sender,
            propertyTokens
        );

        assert(!isInvestor[msg.sender]);
        isInvestor[msg.sender] = true;
        investors.push(msg.sender);

        assert(holdStartTime[msg.sender][_propertyId] == 0);
        holdStartTime[msg.sender][_propertyId] = block.timestamp;

        emit Invested(msg.sender, _propertyId, msg.value, propertyTokens);
    }

    function withdraw(uint256 _propertyId) external whenNotPaused {
        Property storage property = properties[_propertyId];
        uint256 investedAmount = userInvestments[msg.sender][_propertyId];
        require(investedAmount > 0, "No investment found");

        uint256 tokenPrice = getTokenPrice(_propertyId);
        require(tokenPrice > 0, "Token price invalid");

        uint256 propertyTokensToBurn = investedAmount / tokenPrice;

        userInvestments[msg.sender][_propertyId] = 0;
        property.investedAmount -= investedAmount;
        holdStartTime[msg.sender][_propertyId] = 0;

        ERC20(tokenAddress).transfer(msg.sender, investedAmount);
        PropertyToken(property.propertyToken).burn(
            msg.sender,
            propertyTokensToBurn
        );

        emit Withdrawn(
            msg.sender,
            _propertyId,
            investedAmount,
            propertyTokensToBurn
        );
    }

    function distributeRewards() public whenNotPaused {
        require(
            block.timestamp >=
                lastRewardDistribution + REWARD_DISTRIBUTION_PERIOD,
            "Rewards not due yet"
        );

        for (uint256 i = 1; i <= propertyCounter; i++) {
            Property storage property = properties[i];

            if (property.investedAmount == 0) continue;

            uint256 totalRewardsForProperty = (property.investedAmount *
                property.annualRewardRate) /
                100 /
                12;

            for (uint256 j = 0; j < investors.length; j++) {
                address user = investors[j];

                uint256 userInvestment = userInvestments[user][i];
                if (
                    userInvestment > 0 &&
                    block.timestamp >= holdStartTime[user][i] + MIN_HOLD_TIME
                ) {
                    uint256 userReward = (userInvestment *
                        totalRewardsForProperty) / property.investedAmount;

                    if (userReward > 0) {
                        accumulatedReward[user] += userReward;
                        ERC20(tokenAddress).safeTransfer(user, userReward);
                        emit RewardDistributed(user, userReward);
                    }
                }
            }
        }

        lastRewardDistribution = block.timestamp;
    }

    function checkUpkeep(
        bytes calldata
    ) external view override returns (bool upkeepNeeded, bytes memory) {
        upkeepNeeded =
            (block.timestamp - lastRewardDistribution) >
            REWARD_DISTRIBUTION_PERIOD;
    }

    function performUpkeep(bytes calldata) external override {
        require(
            (block.timestamp - lastRewardDistribution) >
                REWARD_DISTRIBUTION_PERIOD,
            "Not time yet"
        );
        distributeRewards();
    }

    function pauseContract() external onlyOwner {
        _pause();
    }

    function unpauseContract() external onlyOwner {
        _unpause();
    }
}
