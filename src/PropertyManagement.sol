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

    uint256 public constant TOTAL_TOKENS = 1_000_000;
    uint256 public constant MIN_HOLD_TIME = 1 days;
    uint256 public constant REWARD_DISTRIBUTION_PERIOD = 30 days;
    uint256 public lastRewardDistribution;

    mapping(uint256 => Property) public properties;
    mapping(address => mapping(uint256 => uint256)) public userInvestments;
    mapping(address => uint256) public holdStartTime;
    mapping(address => uint256) public accumulatedReward;

    AggregatorV3Interface internal priceFeed;
    uint256 public propertyCounter;

    address public tokenAddress; // Address of the deployed My10BToken contract

    event PropertyCreated(
        uint256 indexed propertyId,
        string name,
        uint256 totalSupply,
        uint256 annualRewardRate,
        address propertyToken
    );

    event Invested(address indexed user, uint256 propertyId, uint256 amount);
    event Withdrawn(address indexed user, uint256 propertyId, uint256 amount);
    event RewardDistributed(address indexed user, uint256 amount);

    constructor(address _priceFeed, address _tokenAddress) Ownable(msg.sender) {
        // Call Ownable constructor explicitly
        priceFeed = AggregatorV3Interface(_priceFeed);
        tokenAddress = _tokenAddress; // Set token contract address
        lastRewardDistribution = block.timestamp;
    }

    // Admin creates a property token for investments
    function createProperty(
        string memory _name,
        uint256 _totalSupply,
        uint256 _annualRewardRate
    ) external onlyOwner {
        require(_annualRewardRate > 0, "Annual reward rate must be positive");

        PropertyToken newToken = new PropertyToken(_name, _name, msg.sender);

        propertyCounter++;
        properties[propertyCounter] = Property({
            name: _name,
            totalSupply: _totalSupply,
            totalRaised: 0,
            annualRewardRate: _annualRewardRate,
            investedAmount: 0,
            propertyToken: address(newToken),
            active: true
        });

        emit PropertyCreated(
            propertyCounter,
            _name,
            _totalSupply,
            _annualRewardRate,
            address(newToken)
        );
    }

    function invest(
        uint256 _propertyId,
        uint256 _amount
    ) external whenNotPaused {
        Property storage property = properties[_propertyId];
        require(property.active, "Property is not active");

        ERC20(tokenAddress).transferFrom(msg.sender, address(this), _amount);
        property.investedAmount += _amount;
        property.totalRaised += _amount;
        userInvestments[msg.sender][_propertyId] += _amount;

        // Calculate token price based on totalRaised / totalSupply
        uint256 tokenPrice = property.totalRaised / TOTAL_TOKENS;
        uint256 propertyTokensToMint = _amount / tokenPrice;

        ERC20(property.propertyToken).transfer(
            msg.sender,
            propertyTokensToMint
        );

        emit Invested(msg.sender, _propertyId, _amount);
    }

    function withdraw(uint256 _propertyId) external whenNotPaused {
        Property storage property = properties[_propertyId];
        uint256 amount = userInvestments[msg.sender][_propertyId];
        require(amount > 0, "No investment found");

        userInvestments[msg.sender][_propertyId] = 0;
        property.investedAmount -= amount;

        // Calculate token price based on totalRaised / totalSupply
        uint256 tokenPrice = property.totalRaised / TOTAL_TOKENS;
        uint256 propertyTokensToBurn = amount / tokenPrice;

        ERC20(tokenAddress).transfer(msg.sender, amount);
        ERC20(property.propertyToken).transferFrom(
            msg.sender,
            address(this),
            propertyTokensToBurn
        );

        emit Withdrawn(msg.sender, _propertyId, amount);
    }

    // Chainlink Keeper function to automate reward distribution every 30 days
    function checkUpkeep(
        bytes calldata /*checkData*/
    )
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory performData)
    {
        upkeepNeeded =
            (block.timestamp - lastRewardDistribution) >
            REWARD_DISTRIBUTION_PERIOD;
        performData = ""; // Explicitly setting an empty bytes value
    }

    function performUpkeep(bytes calldata /*performData*/) external override {
        require(
            (block.timestamp - lastRewardDistribution) >
                REWARD_DISTRIBUTION_PERIOD,
            "Not time yet"
        );
        distributeRewards();
        lastRewardDistribution = block.timestamp;
    }

    // Distribute rewards to all investors
    function distributeRewards() public whenNotPaused {
        for (uint256 i = 1; i <= propertyCounter; i++) {
            for (uint256 j = 0; j < address(this).balance; j++) {
                address user = address(
                    uint160(
                        uint256(keccak256(abi.encodePacked(block.timestamp, j)))
                    )
                );
                if (accumulatedReward[user] > 0) {
                    // Use safeTransfer from SafeERC20
                    ERC20(tokenAddress).safeTransfer(
                        user,
                        accumulatedReward[user]
                    );
                    emit RewardDistributed(user, accumulatedReward[user]);
                    accumulatedReward[user] = 0;
                }
            }
        }
    }

    function getTokenPrice(uint256 _propertyId) public view returns (uint256) {
        Property storage property = properties[_propertyId];
        if (property.totalRaised == 0) return 0;
        return property.totalRaised / TOTAL_TOKENS;
    }

    // Admin manually distributes MY10B tokens for traditional investors
    function distributeTraditionalPayment(
        address user,
        uint256 amount
    ) external onlyOwner {
        // Use safeTransfer from SafeERC20
        ERC20(address(this)).safeTransfer(user, amount);
    }

    // Pause and Unpause the contract
    function pauseContract() external onlyOwner {
        _pause();
    }

    function unpauseContract() external onlyOwner {
        _unpause();
    }
}
