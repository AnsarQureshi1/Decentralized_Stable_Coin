//SPDX-License-Identifier:MIT

pragma solidity ^0.8.20;

import {PakCoin} from "./PakCoin.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "../lib/chainlink-brownie-contracts/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract PKCEngine {
    error PKCEngine__MoreThanZero();
    error PKCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error PKCEngine__NotAllowedToken();
    error PKCEngine__TransferFailed();
    error PKCEngine__BreaksHealthFactor(uint userHealthFactor);
    error PKCEngine__MintFailed();
    error PKCEngine__HealthFactorOk();
    error PKCEngine__HealthFactorNotImproved();

    uint private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint private constant PRECISION = 1e18;
    uint private constant LIQUIDATION_THRESHOLD = 50;
    uint private constant LIQUIDATION_PRECISION = 100;
    uint private constant MIN_HEALTH_FACTOR = 1e18;
    uint private constant LIQUIDATION_BONUS = 10;

    mapping(address Token => address PriceFeedAddress) private s_priceFeeds;
    mapping(address User => mapping(address Token => uint256))
        private s_collateralDeposited;
    mapping(address user => uint256 amountMinted) private s_PKCMinted;
    address[] private s_collateralTokens;
    PakCoin private immutable i_pkc;

    event CollateralDeposited(
        address indexed user,
        address indexed token,
        uint indexed amount
    );

    event CollateralRedeemed(
        address indexed redremedFrom,
        address indexed redremedTo,
        uint indexed amount,
        address token
    );

    modifier moreThanZero(uint amount) {
        if (amount <= 0) {
            revert PKCEngine__MoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert PKCEngine__NotAllowedToken();
        }
        _;
    }

    constructor(
        address[] memory tokenAddresses,
        address[] memory priceFeedAddresses,
        address pkcAddress
    ) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert PKCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }
        for (uint i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_pkc = PakCoin(pkcAddress);
    }

    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint amountCollateral,
        uint amountPkcToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountPkcToMint);
    }

    function depositCollateral(
        address tokenCollateralAddress,
        uint amountCollateral
    )
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
    {
        s_collateralDeposited[msg.sender][
            tokenCollateralAddress
        ] += amountCollateral;
        emit CollateralDeposited(
            msg.sender,
            tokenCollateralAddress,
            amountCollateral
        );
        bool success = IERC20(tokenCollateralAddress).transferFrom(
            msg.sender,
            address(this),
            amountCollateral
        );
        if (!success) {
            revert PKCEngine__TransferFailed();
        }
    }

    function redeemCollateralForDsc(
        address tokenCollateralAddress,
        uint amountCollateral,
        uint amountPkcToBurn
    ) external {
        burnDsc(amountPkcToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
    }

    function redeemCollateral(
        address tokenCollateralAddress,
        uint amountCollateral
    ) public moreThanZero(amountCollateral) {
        _redeemCollateral(
            tokenCollateralAddress,
            amountCollateral,
            msg.sender,
            msg.sender
        );
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function mintDsc(
        uint256 amountPkcToMint
    ) public moreThanZero(amountPkcToMint) {
        s_PKCMinted[msg.sender] += amountPkcToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_pkc.mint(msg.sender, amountPkcToMint);
        if (!minted) {
            revert PKCEngine__MintFailed();
        }
    }

    function burnDsc(uint amount) public moreThanZero(amount) {
        _burnDsc(amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender); // this line never hit
    }

    function liquidate(
        address collateral,
        address user,
        uint deptToCover
    ) external moreThanZero(deptToCover) {
        uint startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert PKCEngine__HealthFactorOk();
        }

        uint tokenAmountFromDebtCovered = getTokenAmountFromUsd(
            collateral,
            deptToCover
        );
        uint256 bonusCollateral = (tokenAmountFromDebtCovered *
            LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered +
            bonusCollateral;
        _redeemCollateral(
            collateral,
            totalCollateralToRedeem,
            user,
            msg.sender
        );
        _burnDsc(deptToCover, user, msg.sender);

        uint endingUserHealthFactor = _healthFactor(user);

        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert PKCEngine__HealthFactorNotImproved();
        }

        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function _burnDsc(
        uint256 amountPkcToBurn,
        address onBehalfOf,
        address pkcFrom
    ) private {
        s_PKCMinted[onBehalfOf] -= amountPkcToBurn;
        bool success = i_pkc.transferFrom(
            pkcFrom,
            address(this),
            amountPkcToBurn
        );
        if (!success) {
            revert PKCEngine__TransferFailed();
        }
        i_pkc.burn(amountPkcToBurn);
    }
    function _redeemCollateral(
        address totalCollateralToRedeem,
        uint amountCollateral,
        address from,
        address to
    ) private {
        s_collateralDeposited[from][
            totalCollateralToRedeem
        ] -= amountCollateral;
        emit CollateralRedeemed(
            from,
            to,
            amountCollateral,
            totalCollateralToRedeem
        );
        bool success = IERC20(totalCollateralToRedeem).transfer(
            to,
            amountCollateral
        );
        if (!success) {
            revert PKCEngine__TransferFailed();
        }
    }

    function _getAccountInformation(
        address user
    ) private view returns (uint totalPKCMinted, uint collateralValueInUsd) {
        totalPKCMinted = s_PKCMinted[user];
        collateralValueInUsd = getAccountCollateralValueInUsd(user);
    }
    function _healthFactor(address user) private view returns (uint256) {
        (
            uint totalPkcMinted,
            uint collateralValueInUsd
        ) = _getAccountInformation(user);
        return _calculateHealthFactor(totalPkcMinted, collateralValueInUsd);
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert PKCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    function _calculateHealthFactor(
        uint totalPkcMinted,
        uint collateralValueInUsd
    ) internal pure returns (uint) {
        if (totalPkcMinted == 0) return type(uint).max;
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd *
            LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalPkcMinted;
    }

    function getTokenAmountFromUsd(
        address token,
        uint usdAmountInWei
    ) public view returns (uint) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeeds[token]
        );
        (, int256 price, , , ) = priceFeed.latestRoundData();
        return
            (usdAmountInWei * PRECISION) /
            (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    function getAccountCollateralValueInUsd(
        address user
    ) public view returns (uint totalCollateralValueInUsd) {
        for (uint i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    function getUsdValue(
        address token,
        uint amount
    ) public view returns (uint) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeeds[token]
        );
        (, int256 price, , , ) = priceFeed.latestRoundData();
        return
            ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    function getAccountInformation(
        address user
    ) external view returns (uint totalPkcMinted, uint collateralValueInUSD) {
        (totalPkcMinted, collateralValueInUSD) = _getAccountInformation(user);
    }

    function getHealthFactor(address user) public view returns (uint totalPkcMinted) {
        return _healthFactor(user);
    }

    function calculateHealthFactor(
        uint totalPkcMinted,
        uint collateralValueInUSD
    ) external view returns (uint) {
        return _calculateHealthFactor(totalPkcMinted, collateralValueInUSD);
    }

    function getCollateralTokens() external view returns(address[] memory){
        return s_collateralTokens;
    }

    function getCollateralBalanceOfUser(address user, address token) external view returns(uint){
        return s_collateralDeposited[user][token];
    }
}
