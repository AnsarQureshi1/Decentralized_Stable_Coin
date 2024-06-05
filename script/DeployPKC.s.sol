// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Script } from "forge-std/Script.sol";
import { HelperConfig } from "./HelperConfig.s.sol";
import { PakCoin } from "../src/PakCoin.sol";
import { PKCEngine } from "../src/PakCoinEngine.sol";

contract DeployPKC is Script {
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function run() external returns (PakCoin, PKCEngine, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig(); // This comes with our mocks!

        (address wethUsdPriceFeed, address wbtcUsdPriceFeed, address weth, address wbtc, uint256 deployerKey) =
            helperConfig.activeNetworkConfig();
        tokenAddresses = [weth, wbtc];
        priceFeedAddresses = [wethUsdPriceFeed, wbtcUsdPriceFeed];

        vm.startBroadcast(deployerKey);
        PakCoin pkc = new PakCoin("","");
        PKCEngine pkcEngine = new PKCEngine(tokenAddresses, priceFeedAddresses, address(pkc));
        
        pkc.transferOwnership(address(pkcEngine));
        vm.stopBroadcast();

     

        return (pkc, pkcEngine, helperConfig);
    }
}