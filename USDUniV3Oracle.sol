// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import "../interfaces/IERC20Decimal.sol";
import "../interfaces/IOracle.sol";
import "../libraries/OracleMath.sol";
import "@uniswap/v3-core/contracts/interfaces/pool/IUniswapV3PoolImmutables.sol";
import "@uniswap/v3-core/contracts/interfaces/pool/IUniswapV3PoolState.sol";
import "@uniswap/v3-core/contracts/libraries/FullMath.sol";
import "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";
import "@uniswap/v3-periphery/contracts/libraries/PoolAddress.sol";

// @title USDC Uniswap V3 Oracle
// Provide function to compute the price of tokens listed on uniswap
contract USDUniV3Oracle is IOracle {
    /// @dev the latestAnswer returned
    uint256 private latestAnswer;
    // The average price period we want to compute in seconds
    uint32 public constant PERIOD = 3600;

    bool private immutable isBaseToken;

    IUniswapV3PoolImmutables public immutable pool;

    // @notice create a new price oracle centered around one pair, one of the token MUST be USDC
    constructor(IUniswapV3PoolImmutables _pool, bool _isBaseToken) {
        require(IUniswapV3PoolState(address(_pool)).liquidity() > 0, "UV3: Pool has no liquidity");
        pool = _pool;
        isBaseToken = _isBaseToken;
    }

    // @notice Get the price token in USDC or USDT, rounded to 8 decimals
    function getPriceInUSD() external override returns (uint256 price) {
        int24 tick = OracleLibrary.consult(address(pool), PERIOD);
        uint256 p = OracleMath.getQuoteAtTick(tick, pool.token0(), pool.token1());
        if (!isBaseToken) {
            price = 10**26 / p;
        } else {
            price = p / 10**10;
        }
        emit PriceUpdated(isBaseToken ? pool.token0() : pool.token1(), price);
        latestAnswer = price;
    }

    function viewPriceInUSD() external view override returns (uint256) {
        return latestAnswer;
    }
}
