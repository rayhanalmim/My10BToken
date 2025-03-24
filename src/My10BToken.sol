// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {Blacklistable} from "@openzeppelin/contracts/access/Ownable.sol"; 

contract My10BToken is ERC20, Ownable, Pausable {
    mapping(address => bool) private _blacklist;

    constructor(uint256 initialSupply) ERC20("My10B Token", "MY10B") Ownable() {
        _mint(msg.sender, initialSupply);
    }

    modifier notBlacklisted(address account) {
        require(!_blacklist[account], "My10BToken: account is blacklisted");
        _;
    }

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function blacklist(address account) external onlyOwner {
        _blacklist[account] = true;
    }

    function removeBlacklist(address account) external onlyOwner {
        _blacklist[account] = false;
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal whenNotPaused override {
        super._beforeTokenTransfer(from, to, amount);
        require(!_blacklist[from] && !_blacklist[to], "My10BToken: sender or receiver is blacklisted");
    }
}
