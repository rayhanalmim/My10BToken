// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

error EnforcedPause();

contract My10BToken is ERC20, Ownable, Pausable {
    uint256 public immutable i_MAX_SUPPLY;

    constructor(
        uint256 initialSupply
    ) ERC20("Taka", "BDT") Ownable(msg.sender) {
        require(initialSupply > 0, "Initial supply must be greater than zero");
        i_MAX_SUPPLY = initialSupply;
    }

    function mint(address to, uint256 amount) external onlyOwner {}
}
