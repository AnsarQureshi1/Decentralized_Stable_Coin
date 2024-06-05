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


contract PKCEngineTest is Test {

    error PKCEngine__MoreThanZero();
    error PKCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error PKCEngine__NotAllowedToken();
    error PKCEngine__TransferFailed();
    error PKCEngine__BreaksHealthFactor(uint userHealthFactor);
    error PKCEngine__MintFailed();
    error PKCEngine__HealthFactorOk();
    error PKCEngine__HealthFactorNotImproved();

    DeployPKC deployer;
    PakCoin pkc;
    PKCEngine engine;
    HelperConfig config;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;
    address wbtc;

    address public USER = makeAddr("user");
    uint256 public constant STARTING_USER_BALANCE = 10 ether;
    uint public constant AMOUNT_COLLATERAL = 10 ether;
    uint amountToMint = 100 ether;
    address[] tokenAddresses;
    address[] priceFeedAddresses;


    address public liquidator = makeAddr("liquidator");
    uint256 public collateralToCover = 20 ether;

    function setUp() external {
        deployer = new DeployPKC();
        (pkc, engine,config) = deployer.run();
        (ethUsdPriceFeed,btcUsdPriceFeed,weth,wbtc,) = config.activeNetworkConfig();
        // if (block.chainid == 31_337) {
        //     vm.deal(user, STARTING_USER_BALANCE);
        // }
        ERC20Mock(weth).mint(USER, STARTING_USER_BALANCE);
        ERC20Mock(wbtc).mint(USER, STARTING_USER_BALANCE);
    }
    

    function test__GetUsdValue() public {
        uint ethAmount = 30e18;

        // 30e18 * 3500 = 105000e18
        uint expectedUsd = 105000e18;

        uint actualUsd = engine.getUsdValue(weth,ethAmount);
        assertEq(expectedUsd, actualUsd);
    }

    function test__UsdAmount() public {
        uint usdAmount = 200 ether;

        // 200e18 / 3500
        uint expectedWeth = 0.0571428571429 ether;
        uint actualWeth = engine.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectedWeth, actualWeth); 
    }

    function test__GetBTCValue() public {
        uint ethAmount = 10e18;

        // 10e18 * 1500 = 105000e18
        uint expectedUsd = 15000e18;

        uint actualUsd = engine.getUsdValue(wbtc,ethAmount);
        assertEq(expectedUsd, actualUsd);
    }


    ////////////////////////
    /// Deposit Collateral test
    /////////////////////

    function test__RevertWhenCollateralIsZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        vm.expectRevert(PKCEngine.PKCEngine__MoreThanZero.selector);
        engine.depositCollateral(weth, 0);
        vm.stopPrank();
    }


    function test__DepostingCollateral() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function test__RevertOnNotAllowedToken() public {
        vm.startPrank(USER);
        vm.expectRevert();
        engine.depositCollateral(address(this), 200);
        vm.stopPrank();
    }

    modifier depositCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine),AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function test__DepositCollateralAndGetAccountInfo() external depositCollateral {
        (uint totalPKCMinted, uint collateralValueInUSD) = engine.getAccountInformation(USER);

        uint expectedTotalPKCMinted = 0;
        uint expectedDepositAmount = engine.getTokenAmountFromUsd(weth, collateralValueInUSD);
        assertEq(totalPKCMinted, expectedTotalPKCMinted);
        assertEq(AMOUNT_COLLATERAL,expectedDepositAmount);
    }


    function test__DepositCollateralAndMintDsc() external  {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine),AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, 3 ether);
        vm.stopPrank();
        (uint mintedPKC, uint collateralValueInUsd) = engine.getAccountInformation(USER);
        uint expectedTotalPKCMinted = 3 ether;
        uint expectedDepositAmount = engine.getTokenAmountFromUsd(weth,collateralValueInUsd);
        assertEq(mintedPKC, expectedTotalPKCMinted);
        assertEq(AMOUNT_COLLATERAL,expectedDepositAmount);

        
    }

    ////////////////////////////////////
    //// deposit collateral and mint DSC 
    ////////////////////////////////////

    function test__RevertIfMintedDSCBreaksHealthFactor() public {
        (,int256 price,,,) = MockV3Aggregator(ethUsdPriceFeed).latestRoundData();
        console.logInt(price);
        amountToMint = (AMOUNT_COLLATERAL *(uint256(price) * 1e10 )) / 1e18 ;
        console.logUint(amountToMint);
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine),AMOUNT_COLLATERAL);
        uint expectedHealthFactor = engine.calculateHealthFactor(amountToMint, engine.getUsdValue(weth, AMOUNT_COLLATERAL));
        console.logUint(expectedHealthFactor);
        vm.expectRevert(abi.encodeWithSelector(PKCEngine.PKCEngine__BreaksHealthFactor.selector, expectedHealthFactor));
        engine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, amountToMint);
        vm.stopPrank();

    }

    function test__WbtcRevertIfMintedDSCBreaksHealthFactor() public {
        (,int256 price,,,) = MockV3Aggregator(btcUsdPriceFeed).latestRoundData();
        console.logInt(price);
        amountToMint = (AMOUNT_COLLATERAL *(uint256(price) * 1e10 )) / 1e18 ;
        console.logUint(amountToMint);
        vm.startPrank(USER);
        ERC20Mock(wbtc).approve(address(engine),AMOUNT_COLLATERAL);
        console.logUint(engine.getUsdValue(wbtc, AMOUNT_COLLATERAL));
        uint expectedHealthFactor = engine.calculateHealthFactor(amountToMint, engine.getUsdValue(wbtc, AMOUNT_COLLATERAL));
        console.logUint(expectedHealthFactor);
        vm.expectRevert(abi.encodeWithSelector(PKCEngine.PKCEngine__BreaksHealthFactor.selector, expectedHealthFactor));
        engine.depositCollateralAndMintDsc(wbtc, AMOUNT_COLLATERAL, amountToMint);
        vm.stopPrank();

    }

    function test__DepositCollateralMintDSC() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, amountToMint);
        uint value = engine.getUsdValue(weth,AMOUNT_COLLATERAL);
        console.log(engine.calculateHealthFactor(amountToMint, value));
        vm.stopPrank();

        uint userBalance = pkc.balanceOf(USER);
        assertEq(userBalance, amountToMint); 
        console.log(userBalance);
    }

    function test__BTCDepositAndMint() public {
        
        vm.startPrank(USER);
        ERC20Mock(wbtc).approve(address(engine), 0.001 ether);
        vm.expectRevert(abi.encodeWithSelector(PKCEngine.PKCEngine__BreaksHealthFactor.selector));
        engine.depositCollateralAndMintDsc(wbtc, 0.001 ether , 200 ether);
        uint value = engine.getUsdValue(wbtc,0.001 ether);
        console.log(value);
        console.log(engine.calculateHealthFactor(200 ether, value));
        vm.stopPrank();

        uint userBalance = pkc.balanceOf(USER);
      
    
    }

    modifier depositedCollateralAndMintedDsc() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine),AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, amountToMint);
        vm.stopPrank();
        _;
    }


    /////////////////////
    /// constructor test
    /////////////////////

    function test__ConstructorTest() public {
        tokenAddresses.push(wbtc);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(PKCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength.selector);
        new PKCEngine(tokenAddresses,priceFeedAddresses,address(pkc));
    }

    //////////////////////////////////
    ///////////////health factor test
    /////////////////////////////////

    function test__healthFactor() public depositedCollateralAndMintedDsc {
        uint expectedHealthFactor = 175 ether;
        // $100 minted $35000 collateral
        // at 50% liquidation
        // 35000 *0.5 = 17500
        // 17500 / 100 = 100
        uint healthFactor = engine.getHealthFactor(USER);
        assertEq(expectedHealthFactor, healthFactor);
        console.log(healthFactor);
    }

    function testHealthFactorCanGoBelowOne() public depositedCollateralAndMintedDsc {
        int256 ethUsdUpdatedPrice = 18e8; // 1 ETH = $18
        // Rememeber, we need $200 at all times if we have $100 of debt

        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);

        uint256 userHealthFactor = engine.getHealthFactor(USER);
        // 180*50 (LIQUIDATION_THRESHOLD) / 100 (LIQUIDATION_PRECISION) / 100 (PRECISION) = 90 / 100 (totalDscMinted) =
        // 0.9
        console.log(userHealthFactor);
        assert(userHealthFactor == 0.9 ether);
    }

    //////////////////////////////////
    /////////// Liquidity/////////////
    //////////////////////////////////


    function test__RevertWhenHealthFactorIsOk() public depositedCollateralAndMintedDsc {

        ERC20Mock(weth).mint(liquidator, collateralToCover);
        vm.startBroadcast(liquidator);
        ERC20Mock(weth).approve(address(engine),collateralToCover);
        engine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, amountToMint);
        pkc.approve(address(engine), amountToMint);

        vm.expectRevert(PKCEngine.PKCEngine__HealthFactorOk.selector);
        engine.liquidate(weth, USER, amountToMint);
        vm.stopPrank();
        
    }

    function test__Liquidation() public depositedCollateralAndMintedDsc {

        uint beforeHealthFactor = engine.getHealthFactor(USER);
        console.log(beforeHealthFactor);

        int256 ethUsdUpdatedPrice = 12e8;
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);

        uint healthFactor = engine.getHealthFactor(USER);
        console.log(healthFactor);

        ERC20Mock(weth).mint(liquidator,collateralToCover);

        vm.startPrank(liquidator);
        ERC20Mock(weth).approve(address(engine),collateralToCover);
        engine.depositCollateralAndMintDsc(weth, collateralToCover, amountToMint);
        pkc.approve(address(engine), amountToMint);
        engine.liquidate(weth, USER, amountToMint);
        vm.stopPrank();

        uint liquidatorHealth = engine.getHealthFactor(liquidator);
        console.log(liquidatorHealth);

        uint liquidatorWethBalance = ERC20Mock(weth).balanceOf(liquidator);

        console.log(liquidatorWethBalance);

        uint256 expectedWeth = engine.getTokenAmountFromUsd(weth, amountToMint)
            + (engine.getTokenAmountFromUsd(weth, amountToMint) / 10);

        console.log(expectedWeth);

        assertEq(liquidatorWethBalance, expectedWeth);
        
    }


    /////////////////////////////////////////////
    ///////// Redeeem Collateral ////////////////
    /////////////////////////////////////////////


    function test__RevertMoreThanZer0RedeemCollateral() public depositedCollateralAndMintedDsc {
        vm.startPrank(USER);
        vm.expectRevert(PKCEngine.PKCEngine__MoreThanZero.selector);
        engine.redeemCollateralForDsc(weth, AMOUNT_COLLATERAL, 0);
        vm.stopPrank();
    }

    function test__RedeemCollateral() public depositedCollateralAndMintedDsc {
        pkc.balanceOf(USER);
        assertEq(100 ether, amountToMint);
        console.log(ERC20Mock(weth).balanceOf(USER));
        assertEq(0, ERC20Mock(weth).balanceOf(USER));
        vm.startPrank(USER);
        pkc.approve(address(engine), amountToMint);
        engine.redeemCollateralForDsc(weth, AMOUNT_COLLATERAL , amountToMint);
        vm.stopPrank();
        assertEq(0, pkc.balanceOf(USER));
        assertEq(10 ether, ERC20Mock(weth).balanceOf(USER));
    }

    function test__RevertIfHealthFactorIsBrokenWhileRedeeming() public depositedCollateralAndMintedDsc {

        int256 ethUsdUpdatedPrice = 6e8;
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);
        console.log(engine.getHealthFactor(USER));
        vm.startPrank(USER);
        vm.expectRevert();
        engine.redeemCollateralForDsc(weth, AMOUNT_COLLATERAL, amountToMint);
        vm.stopPrank();
    }
    

    

     



}