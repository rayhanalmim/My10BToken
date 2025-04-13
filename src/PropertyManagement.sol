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
    uint256 public constant TOTAL_PROPERTY_TOKENS = 100000 * 1e18;
    uint256 public lastRewardDistribution;

    address[] public investors;
    mapping(address => bool) public isInvestor;
    mapping(uint256 => Property) public properties;
    mapping(address => mapping(uint256 => uint256)) public userInvestments;
    mapping(address => mapping(uint256 => uint256)) public holdStartTime;
    mapping(address => uint256) public accumulatedReward;
    mapping(address => mapping(uint256 => uint256)) public lastClaimed;

    // Traditional Investment Mechanism
    mapping(bytes32 => uint256) public frozenInvestments;
    mapping(address => bool) public isTraditionalInvestor;
    mapping(address => mapping(bytes32 => bool)) public hasClaimedTokens;

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
    event Traded(
        address indexed from,
        address indexed to,
        uint256 propertyId,
        uint256 amount,
        uint256 value
    );

    event RewardDistributed(address indexed user, uint256 amount);

    event TraditionalInvestmentAdded(
        address indexed user,
        uint256 propertyId,
        uint256 amount
    );
    event TraditionalInvestmentClaimed(
        address indexed user,
        uint256 propertyId,
        uint256 amount
    );

    constructor(address _priceFeed, address _tokenAddress) Ownable(msg.sender) {
        priceFeed = AggregatorV3Interface(_priceFeed);
        tokenAddress = _tokenAddress;
        lastRewardDistribution = block.timestamp;
    }

    function createProperty(
        string memory _name,
        string memory _symbol,
        uint256 _totalRaised,
        uint256 _annualRewardRate
    ) external onlyOwner {
        require(_annualRewardRate > 0, "Annual reward rate must be positive");
        require(_totalRaised > 0, "Total raised amount must be positive");

        PropertyToken newToken = new PropertyToken(
            _name,
            _symbol,
            address(this),
            TOTAL_PROPERTY_TOKENS
        );

        propertyCounter++;
        properties[propertyCounter] = Property({
            name: _name,
            totalSupply: TOTAL_PROPERTY_TOKENS,
            totalRaised: _totalRaised,
            annualRewardRate: _annualRewardRate,
            investedAmount: 0,
            propertyToken: address(newToken),
            active: true
        });

        emit PropertyCreated(
            propertyCounter,
            _name,
            TOTAL_PROPERTY_TOKENS,
            _totalRaised,
            _annualRewardRate,
            address(newToken)
        );
    }

    function getTokenPrice(uint256 _propertyId) public view returns (uint256) {
        Property storage property = properties[_propertyId];
        require(property.totalSupply > 0, "Invalid property supply");

        return (property.totalRaised * 1e18) / property.totalSupply;
    }

    function invest(
        uint256 _propertyId,
        uint256 _amount
    ) external whenNotPaused {
        Property storage property = properties[_propertyId];
        require(property.active, "Property is not active");
        require(property.totalRaised > 0, "Total raised must be set");
        require(_amount > 0, "Investment must be > 0");

        ERC20(tokenAddress).safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );

        uint256 propertyTokens = (_amount * TOTAL_PROPERTY_TOKENS) /
            property.totalRaised;
        require(propertyTokens > 0, "Investment too low for tokens");

        uint256 contractTokenBalance = PropertyToken(property.propertyToken)
            .balanceOf(address(this));
        require(
            contractTokenBalance >= propertyTokens,
            "Not enough tokens available"
        );

        if (!isInvestor[msg.sender]) {
            isInvestor[msg.sender] = true;
            investors.push(msg.sender);
        }

        uint256 prevInvestment = userInvestments[msg.sender][_propertyId];
        uint256 newInvestment = _amount;
        uint256 totalInvestment = prevInvestment + newInvestment;

        property.investedAmount += newInvestment;
        userInvestments[msg.sender][_propertyId] = totalInvestment;

        if (prevInvestment == 0) {
            holdStartTime[msg.sender][_propertyId] = block.timestamp;
        } else {
            uint256 prevHoldStart = holdStartTime[msg.sender][_propertyId];
            uint256 newHoldStart = ((prevHoldStart * prevInvestment) +
                (block.timestamp * newInvestment)) / totalInvestment;
            holdStartTime[msg.sender][_propertyId] = newHoldStart;
        }

        ERC20(property.propertyToken).safeTransfer(msg.sender, propertyTokens);

        emit Invested(msg.sender, _propertyId, _amount, propertyTokens);
    }

    function addTraditionalInvestment(
        address _investor,
        uint256 _propertyId,
        string calldata _secret,
        uint256 _amount
    ) external onlyOwner {
        bytes32 secretHash = keccak256(abi.encodePacked(_secret));
        frozenInvestments[secretHash] += _amount;

        isTraditionalInvestor[_investor] = true;

        Property storage property = properties[_propertyId];
        property.investedAmount += _amount;

        emit TraditionalInvestmentAdded(_investor, _propertyId, _amount);
    }

    function claimTokensBySecret(
        string calldata _secret
    ) external whenNotPaused {
        bytes32 secretHash = keccak256(abi.encodePacked(_secret));
        uint256 amount = frozenInvestments[secretHash];

        require(amount > 0, "No frozen investment found for this secret");
        require(
            !hasClaimedTokens[msg.sender][secretHash],
            "Tokens already claimed"
        );

        ERC20(tokenAddress).safeTransfer(msg.sender, amount);

        frozenInvestments[secretHash] = 0;
        hasClaimedTokens[msg.sender][secretHash] = true;

        emit TraditionalInvestmentClaimed(msg.sender, 0, amount);
    }

    function withdraw(
        uint256 _propertyId,
        uint256 _propertyTokensToReturn
    ) external whenNotPaused {
        Property storage property = properties[_propertyId];
        uint256 investedAmount = userInvestments[msg.sender][_propertyId];
        require(investedAmount > 0, "No investment found");

        uint256 tokenPrice = getTokenPrice(_propertyId);
        require(tokenPrice > 0, "Invalid token price");

        uint256 propertyTokenBalance = PropertyToken(property.propertyToken)
            .balanceOf(msg.sender);

        require(
            propertyTokenBalance >= _propertyTokensToReturn,
            "Insufficient property tokens"
        );

        uint256 amountToReturn = _propertyTokensToReturn * tokenPrice;

        require(
            amountToReturn <= investedAmount,
            "Withdrawal exceeds investment"
        );

        uint256 prevInvestment = userInvestments[msg.sender][_propertyId];
        uint256 remainingInvestment = prevInvestment - amountToReturn;

        userInvestments[msg.sender][_propertyId] = remainingInvestment;
        property.investedAmount -= amountToReturn;

        if (remainingInvestment == 0) {
            holdStartTime[msg.sender][_propertyId] = 0;
        } else {
            uint256 oldHoldStart = holdStartTime[msg.sender][_propertyId];
            uint256 nowTime = block.timestamp;

            uint256 withdrawnInvestment = amountToReturn;
            uint256 totalBefore = remainingInvestment + withdrawnInvestment;

            uint256 newHoldStart = ((oldHoldStart * totalBefore) -
                (nowTime * withdrawnInvestment)) / remainingInvestment;

            holdStartTime[msg.sender][_propertyId] = newHoldStart;
        }

        PropertyToken(property.propertyToken).transferFrom(
            msg.sender,
            address(this),
            _propertyTokensToReturn
        );

        ERC20(property.propertyToken).safeTransfer(msg.sender, amountToReturn);

        emit Withdrawn(
            msg.sender,
            _propertyId,
            amountToReturn,
            _propertyTokensToReturn
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
                uint256 holdStart = holdStartTime[user][i];

                if (
                    userInvestment > 0 &&
                    block.timestamp >= holdStart + MIN_HOLD_TIME &&
                    block.timestamp >=
                    lastClaimed[user][i] + REWARD_DISTRIBUTION_PERIOD
                ) {
                    uint256 userReward = (userInvestment *
                        totalRewardsForProperty) / property.investedAmount;

                    if (userReward > 0) {
                        accumulatedReward[user] += userReward;
                        ERC20(tokenAddress).safeTransfer(user, userReward);
                        lastClaimed[user][i] = block.timestamp;
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
        return (upkeepNeeded, "");
    }

    function performUpkeep(bytes calldata) external override {
        require(
            (block.timestamp - lastRewardDistribution) >
                REWARD_DISTRIBUTION_PERIOD,
            "Not time yet"
        );
        distributeRewards();
    }

    function tradePropertyTokens(
        uint256 _propertyId,
        address _to,
        uint256 _amount
    ) external whenNotPaused {
        require(_to != address(0), "Invalid recipient");
        require(_amount > 0, "Amount must be > 0");

        Property storage property = properties[_propertyId];
        require(property.active, "Inactive property");

        uint256 senderBalance = PropertyToken(property.propertyToken).balanceOf(
            msg.sender
        );
        require(senderBalance >= _amount, "Insufficient token balance");

        uint256 tokenPrice = getTokenPrice(_propertyId);
        require(tokenPrice > 0, "Invalid token price");

        uint256 investmentValue = (_amount * tokenPrice) / 1e18;

        userInvestments[msg.sender][_propertyId] -= investmentValue;

        if (userInvestments[msg.sender][_propertyId] == 0) {
            holdStartTime[msg.sender][_propertyId] = 0;
        }

        if (!isInvestor[_to]) {
            isInvestor[_to] = true;
            investors.push(_to);
        }

        uint256 prevInvestment = userInvestments[_to][_propertyId];
        uint256 totalInvestment = prevInvestment + investmentValue;
        userInvestments[_to][_propertyId] = totalInvestment;

        if (prevInvestment == 0) {
            holdStartTime[_to][_propertyId] = block.timestamp;
        } else {
            uint256 prevHoldStart = holdStartTime[_to][_propertyId];
            uint256 weightedStart = ((prevHoldStart * prevInvestment) +
                (block.timestamp * investmentValue)) / totalInvestment;
            holdStartTime[_to][_propertyId] = weightedStart;
        }

        PropertyToken(property.propertyToken).transferFrom(
            msg.sender,
            _to,
            _amount
        );

        emit Traded(msg.sender, _to, _propertyId, _amount, investmentValue);
    }
}
