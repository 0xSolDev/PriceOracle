// SPDX-License-Identifier: MIT
pragma solidity 0.8.1;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IPriceOracleAggregator.sol";
import "../interfaces/IUniswapV2Pair.sol";
import "../libraries/UniswapV2Library.sol";
import "../libraries/UniswapV2OracleLibrary.sol";
import "../math/PRBMathSD59x18.sol";

////////////////////////////////////////////////////////////////////////////////////////////
/// @title UniswapV2Oracle
/// @author @commonlot
/// @notice oracle for assets of uniswapv2 pair
////////////////////////////////////////////////////////////////////////////////////////////

contract UniswapV2Oracle is IOracle {
    /// @notice aggregator of price oracle for assets
    IPriceOracleAggregator public immutable aggregator;

    /// @dev the latestAnser returned
    uint256 private latestAnswer;

    /// @notice period for recomputing the average price
    uint256 public constant PERIOD = 24 hours;

    /// @notice uniswapv2 pair
    IUniswapV2Pair public immutable pair;

    /// @dev return true if baseToken is the firstToken of uniswapv2 pair
    bool public isFirstToken;

    /// @notice address to first token of uniswapv2 pair
    address public immutable token0;

    /// @notice address to second token of uniswapv2 pair
    address public immutable token1;

    /// @dev uniswapv2pair accumulated price value (1 / 0)
    uint256 public price0CumulativeLast;

    /// @dev uniswapv2pair accumulated price value (0 / 1)
    uint256 public price1CumulativeLast;

    /// @dev blockTimestamp for latest updated
    uint32 public blockTimestampLast;

    /// @dev return average price of firstToken in uniswapv2 pair
    uint256 public price0Average;

    /// @dev return average price of secondToken in uniswapv2 pair
    uint256 public price1Average;

    constructor(
        address _factory,
        address _tokenA,
        address _tokenB,
        address _priceOracleAggregator
    ) public {
        require(_priceOracleAggregator != address(0), "UNIV2: Invalid_Aggregator");
        require(_factory != address(0), "UNIV2: Invalid_Factory");
        require(_tokenA != address(0), "UNIV2: Invalid_TokenA");
        require(_tokenB != address(0), "UNIV2: Invalid_TokenB");

        aggregator = IPriceOracleAggregator(_priceOracleAggregator);
        IUniswapV2Pair _pair = IUniswapV2Pair(UniswapV2Library.pairFor(_factory, _tokenA, _tokenB));
        require(address(_pair) != address(0), "UNIV2: Invalid Pair");

        pair = _pair;
        token0 = _pair.token0();
        token1 = _pair.token1();
        price0CumulativeLast = _pair.price0CumulativeLast();
        price1CumulativeLast = _pair.price1CumulativeLast();
        uint112 reserve0;
        uint112 reserve1;
        (reserve0, reserve1, blockTimestampLast) = _pair.getReserves();
        require(reserve0 != 0 && reserve1 != 0, "UNIV2: NO_LIQUIDITY");

        if (_tokenA == _pair.token0()) {
            isFirstToken = true;
        } else {
            isFirstToken = false;
        }
    }

    /// @dev update the cumulative price for the observation at the current timestamp. each observation is updated at most
    /// once per epoch period.
    function update() public {
        (uint256 price0Cumulative, uint256 price1Cumulative, uint32 blockTimestamp) =
            UniswapV2OracleLibrary.currentCumulativePrices(address(pair));
        uint32 timeElapsed = blockTimestamp - blockTimestampLast;

        // ensure that at least one full period has passed since the last update
        if (timeElapsed >= PERIOD) {
            // overflow is desired, casting never truncates
            // cumulative price is in (uq112x112 price * seconds) units so we simply wrap it after division by time elapsed
            price0Average = uint(PRBMathSD59x18.div(int256(price0Cumulative - price0CumulativeLast), int256(uint256(timeElapsed))));
            price1Average = uint(PRBMathSD59x18.div(int256(price1Cumulative - price1CumulativeLast), int256(uint256(timeElapsed))));

            price0CumulativeLast = price0Cumulative;
            price1CumulativeLast = price1Cumulative;
            blockTimestampLast = blockTimestamp;
        }
    }

    /// @dev update usd price of oracle asset
    function getPriceInUSD() external override returns (uint256 price) {
        update();        

        uint256 aggregatorPrice = aggregator.getPriceInUSD(IERC20(isFirstToken ? token1 : token0));
        require(aggregatorPrice != 0, "Aggregator: Oracle not set");

        uint256 priceAverage = isFirstToken ? price0Average : price1Average;
        require(priceAverage > 0, "UNIV2: PERIOD_NOT_ELAPSED");

        price = priceAverage * aggregatorPrice / (10 ** (pair.decimals() + 18)); // should be divide by 1e18
        latestAnswer = price;
        emit PriceUpdated(isFirstToken ? token0 : token1, price);
    }

    /// @return usd price in 1e8 decimals
    function viewPriceInUSD() external view override returns (uint256) {
        return latestAnswer;
    }
}