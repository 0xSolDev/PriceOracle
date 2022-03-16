// SPDX-License-Identifier: MIT
pragma solidity 0.8.1;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../../interfaces/IOracle.sol";
import "../../interfaces/IPriceOracleAggregator.sol";
import "../../interfaces/ICurveFinance.sol";
import "../../interfaces/IERC20Decimal.sol";

////////////////////////////////////////////////////////////////////////////////////////////
/// @title CurveLPMetaPoolOracle
/// @author @commonlot
/// @notice oracle for Curve.Fi LP Token
////////////////////////////////////////////////////////////////////////////////////////////

contract CurveLPMetaPoolOracle is IOracle {
    /// @notice aggregator of price oracle for assets
    IPriceOracleAggregator public immutable aggregator;

    /// @dev the latestAnser returned
    uint256 private latestAnswer;

    /// @notice Curve Registry
    ICurveRegistry public immutable registry;

    /// @notice address to LP
    address public immutable lp;

    constructor(
        address _registry,
        address _lp,
        address _priceOracleAggregator
    ) public {
        require(_registry != address(0), "CVLP: Invalid Pool Registry");
        require(_lp != address(0), "CVLP: Invalid Pool");
        require(_priceOracleAggregator != address(0), "CVLP: Invalid Aggregator");

        registry = ICurveRegistry(_registry);
        aggregator = IPriceOracleAggregator(_priceOracleAggregator);
        lp = _lp;
    }

    /// @dev calculate Curve.Fi LP token price
    function getLPValue() internal returns(uint256 lpValue) {
        address pool = registry.get_pool_from_lp_token(lp);
        require(pool != address(0), "CVLP: No pool for lp");

        (uint256 n, ) = registry.get_n_coins(pool);
        address[8] memory tokens = registry.get_coins(pool);

        uint256 minPx = uint256(type(int256).max);
        for(uint256 idx = 0; idx < n; idx++) {
            uint256 tokenPx = aggregator.getPriceInUSD(IERC20(tokens[idx]));
            require(tokenPx != 0, "Aggregator: Oracle not set");

            if (tokenPx < minPx) {
                minPx = tokenPx;
            }
        }
        require(minPx != uint256(type(int256).max), "CVLP: No minPx");
        lpValue = minPx * (ICurvePool(pool).get_virtual_price()) / 1e18;
    }

    /// @dev update usd price of oracle asset
    function getPriceInUSD() external override returns (uint256 price) {
        price = getLPValue();

        latestAnswer = price;
        emit PriceUpdated(lp, price);
    }

    /// @return usd price in 1e8 decimals
    function viewPriceInUSD() external view override returns (uint256) {
        return latestAnswer;
    }
}
