// SPDX-License-Identifier: MIT
pragma solidity 0.8.1;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IOracle.sol";
import "../interfaces/IPriceOracleAggregator.sol";
import { ElementPTPriceLibrary } from "../libraries/ElementPTPriceLibrary.sol";
import { DataTypes } from "../libraries/DataTypes.sol";

////////////////////////////////////////////////////////////////////////////////////////////
/// @title ElementFiPTPriceOracle
/// @author @commonlot
/// @notice oracle for Element.Fi Principal Token
////////////////////////////////////////////////////////////////////////////////////////////

contract ElementFiPTPriceOracle is IOracle {
    using DataTypes for DataTypes.ElementPTSpotPriceParams;

    /// @notice aggregator of price oracle for assets
    IPriceOracleAggregator public immutable aggregator;

    /// @dev the latestAnser returned
    uint256 private latestAnswer;

    /// @dev params to calculate ElementPTSpotPrice
    DataTypes.ElementPTSpotPriceParams public params;

    constructor(
        address payable _balVault,
        address _ptPool,
        address _base,
        address _priceOracleAggregator
    ) {
        require(_balVault != address(0), "EFPT: Invalid Vault");
        require(_ptPool != address(0), "EFPT: Invalid Pool");
        require(_base != address(0), "EFPT: Invalid Asset");
        require(_priceOracleAggregator != address(0), "EFPT: Invalid Aggregator");

        aggregator = IPriceOracleAggregator(_priceOracleAggregator);
        params = DataTypes.ElementPTSpotPriceParams(_balVault, _ptPool, _base, 0);
    }

    /// @dev update usd price of oracle asset
    function getPriceInUSD() external override returns (uint256 price) {
        uint256 baseTokenPrice = aggregator.getPriceInUSD(IERC20(params.baseToken));
        require(baseTokenPrice != 0, "Aggregator: Oracle not set");

        uint256 spotPrice = ElementPTPriceLibrary.calcSpotPrice(params);
        require(spotPrice != 0, "Aggregator: ElementFiPTPrice");

        price = baseTokenPrice * spotPrice / 1e18; // should be divide by 1e18
        latestAnswer = price;
        emit PriceUpdated(params.baseToken, price);
    }

    /// @return usd price in 1e8 decimals
    function viewPriceInUSD() external view override returns (uint256) {
        return latestAnswer;
    }
}
