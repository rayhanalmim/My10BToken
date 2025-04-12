// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract PropertyToken is ERC20 {
    constructor(
        string memory name,
        string memory symbol,
        address owner,
        uint256 totalSupply
    ) ERC20(name, symbol) {
        _mint(owner, totalSupply);
    }
}
