// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MockERC20 is Ownable, ERC20 {
    uint256 private SUPPLY = 1456250000 * 10**18;

    uint256 private constant faucetLimit = 5e8 * 10**18;

    constructor(string memory _name_, string memory _symbol_) ERC20(_name_, _symbol_) {
        _mint(msg.sender, SUPPLY);
    }

    function faucet(uint256 _amount) external {
        require(_amount <= faucetLimit, "Faucet limit error");
        _mint(msg.sender, _amount);
    }
}
