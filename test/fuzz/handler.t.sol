// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {DeployPKC} from "../../script/DeployPKC.s.sol";
import {PakCoin} from "../../src/PakCoin.sol";
import {PKCEngine } from "../../src/PakCoinEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import { MockV3Aggregator } from "../mocks/MockV3Aggregator.sol";
import "forge-std/console.sol";
import { StdInvariant } from "forge-std/StdInvariant.sol";

contract Handler is StdInvariant, Test {

    PKCEngine engine;
    PakCoin pkc;

    ERC20Mock weth;
    ERC20Mock wbtc;
    uint public mintIsCalled;
    uint MAX_DEPOSIT_SIZE = type(uint96).max;

    constructor(PKCEngine _engine, PakCoin _pkc){
        pkc = _pkc;
        engine = _engine;
        address[] memory collateralTokens = engine.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);

    }

     function mintDsc(uint amount,uint collateralSeed) public {
        mintIsCalled++;
        // (uint totalPkcMinted, uint collateralValueInUsd) = engine.getAccountInformation(msg.sender);

        // int256 maxPkcMint = (int256(collateralValueInUsd) / 2) - int256(totalPkcMinted);
        // if(maxPkcMint < 0){
        //     return;
        // }
         
        // amount = bound(amount,0,uint(maxPkcMint));
        // if(amount == 0){
        //     return;
        // }
   
        vm.startPrank(pkc.owner());
        engine.mintDsc(amount);
        vm.stopPrank();
       
    }
   

    function depositCollateral(uint collateralSeed, uint amountCollateral) public {
        ERC20Mock collateral =  _getCollateralFromSeed(collateralSeed);
        amountCollateral = bound(amountCollateral,1,MAX_DEPOSIT_SIZE);
        vm.startPrank(msg.sender);
        collateral.mint(msg.sender,amountCollateral);
        collateral.approve(address(engine), amountCollateral);
        engine.depositCollateral(address(collateral),amountCollateral);
    }   



    function redeemCollateral(uint collateralSeed, uint amountCollateral) public {
         ERC20Mock collateral =  _getCollateralFromSeed(collateralSeed);
         uint maxRedeemValue = engine.getCollateralBalanceOfUser(msg.sender, address(collateral));
         amountCollateral = bound(amountCollateral,0,maxRedeemValue);
         if(amountCollateral == 0){
            return;
         }
         engine.redeemCollateral(address(collateral), amountCollateral);
    }

    function _getCollateralFromSeed(uint collateralSeed) private view returns(ERC20Mock){
        if(collateralSeed % 2 == 0){
            return weth;
        }
        return wbtc;
    }

}