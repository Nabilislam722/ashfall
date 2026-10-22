// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @notice Worthless stand-in for HEMI on Hemi Sepolia (there is no official testnet HEMI token).
/// Only used for testing the rewards flow before pointing it at the real token on mainnet.
contract TestHemiToken is ERC20, Ownable {
    constructor(address owner_) ERC20("Test Hemi", "tHEMI") Ownable(owner_) {}

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
}
