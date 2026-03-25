// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.5.0
pragma solidity ^0.8.27;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract SlyUSD is ERC20, Ownable {
    constructor(address initialOwner)
        ERC20("SlyUSD", "slyUSD")
        Ownable(initialOwner)
    {}

    address public USDC = 0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E;
    address public depositHandler;

    function mint(address to, uint256 amount) public onlyOwner {
        ERC20(USDC).transferFrom(msg.sender, depositHandler, amount);
        _mint(to, amount);
    }
}
