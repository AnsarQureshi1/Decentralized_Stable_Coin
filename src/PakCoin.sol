//SPDX-License-Identifier:MIT

pragma solidity ^0.8.20;

import { ERC20 } from "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import { Ownable } from "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";

contract PakCoin is ERC20, Ownable {

    error PakCoin__AmountMuseBeMoreThanZero();
    error PakCoin__NotZeroAddress();
    error PakCoin__BurnAmountExceedsTheBalance();

    string private _name;
    string private _symbol;

    constructor(string memory name_, string memory symbol_) ERC20(name_,symbol_) Ownable(msg.sender){
        _name = name_;
        _symbol = symbol_;
    }

    function mint(address _to, uint _amount) external onlyOwner returns(bool) {

        if(_to == address(0)){
            revert PakCoin__AmountMuseBeMoreThanZero();
        }
        if(_amount <= 0){
            revert PakCoin__AmountMuseBeMoreThanZero(); 
        }

        _mint(_to, _amount);

        return true;

    }

    function burn(uint _amount) external onlyOwner returns(bool) {
        uint balance = balanceOf(msg.sender);
        if(balance < _amount){
            revert PakCoin__BurnAmountExceedsTheBalance();
        }
        if(_amount <= 0){
            revert PakCoin__AmountMuseBeMoreThanZero(); 
        }

        _burn(msg.sender, _amount);

        return true;
    }
}