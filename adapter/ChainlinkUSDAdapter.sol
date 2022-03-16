// SPDX-License-Identifier: MIT
pragma solidity 0.8.1;

import "../../interfaces/IOracle.sol";
import "../../interfaces/IChainlinkV3Aggregator.sol";

contract ChainlinkUSDAdapter is IOracle {
    
    /// @dev asset name
    string public assetName;

    /// @dev asset symbol
    string public assetSymbol;

    /// @notice the asset with the price oracle
    address public immutable asset;

    /// @notice chainlink aggregator with price in USD
    IChainlinkV3Aggregator public immutable aggregator;

    /// @dev the latestAnser returned
    uint256 private latestAnswer;

    constructor(
        string memory _assetName,
        string memory _assetSymbol,
        address _asset,
        IChainlinkV3Aggregator _aggregator
    ) {
        require(_asset != address(0), "invalid asset");
        require(address(_aggregator) != address(0), "invalid aggregator");
        assetName = _assetName;
        assetSymbol = _assetSymbol;
        asset = _asset;
        aggregator = _aggregator;
    }

    /// @dev returns price of asset in 1e8
    function getPriceInUSD() external override returns (uint256 price) {
        (, int256 priceC, , , ) = aggregator.latestRoundData();
        price = uint256(priceC);
        latestAnswer = price;
        emit PriceUpdated(asset, price);
    }

    /// @dev returns the latest price of asset
    function viewPriceInUSD() external view override returns (uint256) {
        return latestAnswer;
    }
}
