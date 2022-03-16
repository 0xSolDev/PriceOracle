// SPDX-License-Identifier: MIT
pragma solidity 0.8.1;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IERC20Decimal.sol";
import "../interfaces/IOracle.sol";
import "../interfaces/IBVaultV2.sol";
import "../interfaces/IBPoolV2.sol";
import "../interfaces/IPriceOracleAggregator.sol";
import "../math/BNum.sol";
import { DataTypes } from "../libraries/DataTypes.sol";

////////////////////////////////////////////////////////////////////////////////////////////
/// @title BPTV2PriceOracle
/// @author @commonlot
/// @notice oracle for Balancer BPT V2
////////////////////////////////////////////////////////////////////////////////////////////

contract BPTV2PriceOracle is BNum, IOracle {
    using DataTypes for DataTypes.BPTV2PriceParams;

    /// @notice aggregator of price oracle for assets
    IPriceOracleAggregator public immutable aggregator;

    /// @dev params to calculate BPT Price
    DataTypes.BPTV2PriceParams public params;

    /// @dev the latestAnser returned
    uint256 private latestAnswer;

    /// @dev decimal expand
    uint256 public constant EXPAND = 10**10;

    /// @dev Balancer Pool address
    IBPoolV2 public pool;

    /// @dev Balancer vault address
    IBVaultV2 public vault;

    /// @dev Balancer Pool's ID
    bytes32 public poolId;

    /// @dev Balancer Pool's tokens
    address[] public tokens;

    /// @dev Balancer Pool tokens' decimals
    uint8[] public decimals;

    /// @dev Balancer Pool tokens' weights
    uint256[] public weights;

    constructor(
        DataTypes.BPTV2PriceParams memory _params,
        address _priceOracleAggregator
    ) {
        require(_priceOracleAggregator != address(0), "BPT: Invalid PriceOracle");
        require(_params.vault != address(0), "BPT: Invalid Vault");
        require(_params.pool != address(0), "BPT: Invalid Pool");

        pool = IBPoolV2(_params.pool);
        vault = IBVaultV2(_params.vault);
        poolId = pool.getPoolId();

        (tokens, ,) = vault.getPoolTokens(poolId);
        uint256 length = tokens.length;

        require(_params.maxPriceDeviation < BONE, "BPT: INVALID_PRICE_DEVIATION");
        require(_params.powerPrecision >= 1 && _params.powerPrecision <= BONE, "BPT: INVALID_POWER_PRECISION");
        require(
            _params.approximationMatrix.length == 0 || _params.approximationMatrix[0].length == length + 1,
            "BPT: INVALID_APPROX_MATRIX"
        );
        
        aggregator = IPriceOracleAggregator(_priceOracleAggregator);
        params = _params;

        uint256[] memory _weights = pool.getNormalizedWeights();
        for (uint8 i = 0; i < length; i++) {
            weights.push(_weights[i]);
            decimals.push(IERC20Decimal(tokens[i]).decimals());
        }
    }

    /**
    * Returns the token balances in USD by multiplying each token balance with its price in USD.
    */
    function getUSDBalances() internal returns (uint256[] memory usdBalances) {
        usdBalances = new uint256[](tokens.length);
        (, uint256[] memory balances ,) = vault.getPoolTokens(poolId);

        for (uint256 index = 0; index < tokens.length; index++) {
            uint256 pi = aggregator.getPriceInUSD(
                IERC20(tokens[index])
            ) * EXPAND;
            require(pi > 0, "BPT: NO_ORACLE");


            uint256 bi;
            // covert current balance to decimal 18
            if (18 >= decimals[index]) {
                bi = bmul(
                    balances[index],
                    BONE * (10 ** (18 - decimals[index]))
                );
            } else {
                bi = bdiv(
                    balances[index] * BONE,
                    (18 - decimals[index] - 18)
                );
            }
            usdBalances[index] = bmul(bi, pi);
        }
    }

    /**
    * Using the matrix approximation, returns a near base and exponentiation result, for num ^ weights[index]
    * @param index Token index.
    * @param num Base to approximate.
    */
    function getClosestBaseAndExponetation(uint256 index, uint256 num) internal view returns (uint256, uint256) {
        uint256 k = index + 1;
        for (uint8 i = 0; i < params.approximationMatrix.length; i++) {
            if (params.approximationMatrix[i][0] >= num) {
                return (
                    params.approximationMatrix[i][0],
                    params.approximationMatrix[i][k]
                );
            }
        }
        return (0, 0);
    }

    /**
    * Returns true if there is a price deviation.
    * @param usdTotals Balance of each token in usd.
    */
    function hasDeviation(uint256[] memory usdTotals) internal view returns (bool) {
        uint256 length = tokens.length;
        for (uint8 i = 0; i < length; i++) {
            for (uint8 o = 0; o < length; o++) {
                if (i != o) {
                    uint256 priceDeviation = bdiv(
                        bdiv(usdTotals[i], weights[i]),
                        bdiv(usdTotals[i], weights[o])
                    );

                    if (
                        priceDeviation > (BONE + params.maxPriceDeviation) ||
                        priceDeviation < (BONE - params.maxPriceDeviation)
                    ) {
                        return true;
                    }
                }
            }
        }
        return false;
    }

    /**
    * Calculates the price of the pool token using the formula of weighted arithmetic mean.
    * @param usdTotals Balance of each token in usd.
    */
    function getArithmeticMean(uint256[] memory usdTotals) internal view returns (uint256) {
        uint256 totalUsd = 0;
        for (uint8 i = 0; i < tokens.length; i++) {
            totalUsd = badd(totalUsd, usdTotals[i]);
        }
        return bdiv(totalUsd, pool.totalSupply());
    }

    /**
    * Returns the weighted token balance in ethers by calculating the balance in ether of the token to the power of its weight.
    * @param index Token index.
    */
    function getWeightedUSDBalanceByToken(uint256 index, uint256 usdTotal) internal view returns (uint256) {
        uint256 weight = weights[index];
        (uint256 base, uint256 result) = getClosestBaseAndExponetation(index, usdTotal);

        if (base == 0 || usdTotal < MAX_BPOW_BASE) {
            if (usdTotal < MAX_BPOW_BASE) {
                return bpowApprox(usdTotal, weight, params.powerPrecision);
            } else {
                return bmul(
                    usdTotal,
                    bpowApprox(
                        bdiv(BONE, usdTotal),
                        (BONE - weight),
                        params.powerPrecision
                    )
                );
            }
        } else {
            return bmul(
                result,
                bpowApprox(
                    bdiv(usdTotal, base),
                    weight,
                    params.powerPrecision
                )
            );
        }
    }

    /**
    * Calculates the price of the pool token using the formula of weighted geometric mean.
    * @param usdTotals Balance of each token in usd.
    */
    function getWeightedGeometricMean(uint256[] memory usdTotals) internal view returns (uint256) {
        uint256 mult = BONE;
        for (uint256 i = 0; i < tokens.length; i++) {
            mult = bmul(
                mult,
                getWeightedUSDBalanceByToken(i, usdTotals[i])
            );
        }
        return bdiv(
            bmul(mult, params.K),
            pool.totalSupply()
        );
    }

    /// @dev update usd price of oracle asset
    function getPriceInUSD() external override returns (uint256 price) {
        uint256[] memory usdTotals = getUSDBalances();

        if(hasDeviation(usdTotals)) {
            price = getWeightedGeometricMean(usdTotals) / EXPAND;
        } else {
            price = getArithmeticMean(usdTotals) / EXPAND;
        }
        latestAnswer = price;
    }

    /// @return usd price in 1e8 decimals
    function viewPriceInUSD() external view override returns (uint256) {
        return latestAnswer;
    }
}