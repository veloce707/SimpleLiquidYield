// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.5.0
pragma solidity ^0.8.27;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

contract TEST is ERC20, ERC20Burnable, Ownable {
 constructor(address _usdc, address _depositHandler) ERC20("TEST", "TEST") Ownable(msg.sender) {
        USDC = IERC20(_usdc);
        depositHandler = _depositHandler;
    }
    using SafeERC20 for IERC20;
    IERC20 public USDC;
    address public depositHandler;

    function mint(address to, uint256 amount) public {
        USDC.safeTransferFrom(msg.sender, address(this), amount);
        _mint(to, amount);
    }

    function redeem( uint256 amount) public {
        uint256 burnAmount = (amount * 50) / 100;
        uint256 remainder = amount - burnAmount;
        _burn(msg.sender, burnAmount);
        transferFrom(msg.sender, address(depositHandler), remainder);
        USDC.safeTransfer(msg.sender, remainder);
        
    }
}
