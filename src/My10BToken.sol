// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

contract My10BToken is ERC20, Ownable, Pausable {

    constructor(uint256 initialSupply) ERC20("My10B Token", "MY10B") Ownable(msg.sender) {
        _mint(msg.sender, initialSupply);
    }

}
