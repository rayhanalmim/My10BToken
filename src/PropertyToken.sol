// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

interface IPropertyManagement {
    function onTokenTransfer(
        address from,
        address to,
        uint256 amount,
        address token
    ) external;
}

contract PropertyToken is ERC20 {
    address public managementContract;

    constructor(
        string memory name,
        string memory symbol,
        address owner,
        uint256 totalSupply
    ) ERC20(name, symbol) {
        _mint(owner, totalSupply);
        managementContract = owner; // PropertyManagement becomes the manager
    }

    function _update(
        address from,
        address to,
        uint256 amount
    ) internal override {
        super._update(from, to, amount);

        if (from != address(0) && to != address(0)) {
            IPropertyManagement(managementContract).onTokenTransfer(
                from,
                to,
                amount,
                address(this)
            );
        }
    }
}
