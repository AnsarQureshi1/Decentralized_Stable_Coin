// // SPDX-License-Identifier: MIT

// pragma solidity ^0.8.19;

// import {Test} from "forge-std/Test.sol";
// import {DeployPKC} from "../../script/DeployPKC.s.sol";
// import {PakCoin} from "../../src/PakCoin.sol";
// import {PKCEngine } from "../../src/PakCoinEngine.sol";
// import {HelperConfig} from "../../script/HelperConfig.s.sol";
// import {ERC20Mock} from "../mocks/ERC20Mock.sol";
// import { MockV3Aggregator } from "../mocks/MockV3Aggregator.sol";
// import "forge-std/console.sol";
// import { StdInvariant } from "forge-std/StdInvariant.sol";

// contract OpenInvariantTest is StdInvariant, Test {

//     DeployPKC deployer;
//     PKCEngine engine;
//     PakCoin pkc;
//     HelperConfig config;
//     address ethUsdPriceFeed;
//     address btcUsdPriceFeed;
//     address weth;
//     address wbtc;

//     function setUp() external {
//         deployer = new DeployPKC();
//         (pkc,engine,config) = deployer.run();
//         (ethUsdPriceFeed,btcUsdPriceFeed,weth,wbtc,) = config.activeNetworkConfig();
//         targetContract(address(engine));
        
//     }


//     function invariant__protocolMustHaveMoreValueThanTotalSupply() public {

//         uint totalSupply = pkc.totalSupply();
//         uint totalWethDeposited = ERC20Mock(weth).balanceOf(address(engine));
//         uint totalWbtcDeposited = ERC20Mock(wbtc).balanceOf(address(engine));

//         uint wethValue = engine.getUsdValue(weth, totalWethDeposited);
//         uint wBtcValue = engine.getUsdValue(wbtc, totalWbtcDeposited);

//         console.log(wethValue);
//         console.log(wBtcValue);
//         console.log(totalSupply);

//         assert(wethValue + wBtcValue >= totalSupply);
//     }
// }