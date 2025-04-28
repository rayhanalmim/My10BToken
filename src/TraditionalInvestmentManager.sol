// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {KeeperCompatibleInterface} from "../lib/chainlink-brownie-contracts/contracts/src/v0.8/automation/interfaces/KeeperCompatibleInterface.sol";
import {AggregatorV3Interface} from "../lib/chainlink-brownie-contracts/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {PropertyToken} from "./PropertyToken.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IPropertyManagement {
    function incrementInvestment(uint256 _propertyId, uint256 _amount) external;
}

contract TraditionalInvestmentManager is Ownable, Pausable {
    using SafeERC20 for ERC20;

    address public tokenAddress;
    IPropertyManagement public propertyManager;

    mapping(bytes32 => uint256) public frozenInvestments;
    mapping(address => bool) public isTraditionalInvestor;
    mapping(address => mapping(bytes32 => bool)) public hasClaimedTokens;
    mapping(bytes32 => uint256) public traditionalInvestmentStartTime;
    mapping(address => mapping(bytes32 => uint256)) public traditionalInvestmentDuration;

    event TraditionalInvestmentAdded(address indexed user, uint256 propertyId, uint256 amount);
    event TraditionalInvestmentClaimed(address indexed user, uint256 propertyId, uint256 amount);

    constructor(address _propertyManager, address _tokenAddress) Ownable(msg.sender) {
        propertyManager = IPropertyManagement(_propertyManager);
        tokenAddress = _tokenAddress;
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
        traditionalInvestmentStartTime[secretHash] = block.timestamp;

        // Update property investment in the main contract
        propertyManager.incrementInvestment(_propertyId, _amount);

        emit TraditionalInvestmentAdded(_investor, _propertyId, _amount);
    }

    function claimTokensBySecret(string calldata _secret) public whenNotPaused {
        bytes32 secretHash = keccak256(abi.encodePacked(_secret));
        uint256 amount = frozenInvestments[secretHash];

        require(amount > 0, "No frozen investment found");
        require(!hasClaimedTokens[msg.sender][secretHash], "Already claimed");

        traditionalInvestmentDuration[msg.sender][secretHash] =
            block.timestamp - traditionalInvestmentStartTime[secretHash];

        ERC20(tokenAddress).safeTransfer(msg.sender, amount);
        frozenInvestments[secretHash] = 0;
        hasClaimedTokens[msg.sender][secretHash] = true;

        emit TraditionalInvestmentClaimed(msg.sender, 0, amount);
    }
}
