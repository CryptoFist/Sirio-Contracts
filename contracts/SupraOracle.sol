// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable2Step.sol";

/**
 * @title Interface for SupraOraclePull
 * @dev Interface to interact with the oracle to pull verified price data.
 */
interface ISupraOraclePull {
    /**
     * @dev Struct to store price data fetched from the oracle.
     * @param pairs Array of asset pair identifiers.
     * @param prices Array of asset prices corresponding to the pairs.
     * @param decimals Array of decimal places for each price.
     */
    struct PriceData {
        uint256[] pairs;
        uint256[] prices;
        uint256[] decimals;
    }

    /**
     * @notice Verifies oracle proof and returns the price data.
     * @param _bytesproof The proof to be verified by the oracle.
     * @return PriceData Struct containing pairs, prices, and decimals.
     */
    function verifyOracleProof(
        bytes calldata _bytesproof
    ) external returns (PriceData memory);
}

/**
 * @title Interface for SupraSValueFeed
 * @dev Interface for getting derived values of asset pairs.
 */
interface ISupraSValueFeed {
    // Data structure to hold the pair data
    struct priceFeed {
        uint256 round;
        uint256 decimals;
        uint256 time;
        uint256 price;
    }
    /**
     * @dev Struct to store derived data from two asset pairs.
     * @param roundDifference The difference in rounds between two pairs.
     * @param derivedPrice The derived price after operation.
     * @param decimals The decimal precision of the derived price.
     */
    struct derivedData {
        int256 roundDifference;
        uint256 derivedPrice;
        uint256 decimals;
    }

    /**
     * @notice Fetches the derived value between two asset pairs.
     * @param pair_id_1 The first pair identifier.
     * @param pair_id_2 The second pair identifier.
     * @param operation The operation to perform (0 for multiplication, 1 for division).
     * @return derivedData Struct containing the result of the operation.
     */
    function getDerivedSvalue(
        uint256 pair_id_1,
        uint256 pair_id_2,
        uint256 operation
    ) external view returns (derivedData memory);

    // Below functions enable you to retrieve different flavours of S-Value
    // Term "pair ID" and "Pair index" both refer to the same, pair index mentioned in our data pairs list.

    // Function to retrieve the data for a single data pair
    function getSvalue(
        uint256 _pairIndex
    ) external view returns (priceFeed memory);

    //Function to fetch the data for a multiple data pairs
    function getSvalues(
        uint256[] memory _pairIndexes
    ) external view returns (priceFeed[] memory);
}

/**
 * @title SupraOracle Contract
 * @notice Integrates with oracle to fetch and derive asset prices.
 * @dev Inherits from Ownable2Step for ownership management.
 */
contract SupraOracle is Ownable2Step {
    /// @notice The oracle contract instance for pulling data.
    ISupraOraclePull public supra_pull;
    /// @notice The storage contract instance for accessing derived values.
    ISupraSValueFeed public supra_storage;

    /// @notice Derived price from the last operation.
    uint256 public dPrice;
    /// @notice Decimal precision of the last derived price.
    uint256 public dDecimal;
    /// @notice Round difference of the last derived value.
    int256 public dRound;

    /// @notice Event emitted when a pair's price is successfully fetched.
    event PairPrice(uint256 pair, uint256 price, uint256 decimals);

    /**
     * @notice Creates a new SupraOracle contract instance.
     * @param oracle_ The initial oracle contract address.
     * @param storage_ The initial storage contract address.
     */
    constructor(
        ISupraOraclePull oracle_,
        ISupraSValueFeed storage_
    ) Ownable(msg.sender) {
        supra_pull = oracle_;
        supra_storage = storage_;
    }

    function GetPrice(uint256 pair) external returns (uint256) {
        //pair index for eth or whatever pair you want
        ISupraSValueFeed.priceFeed memory data = supra_storage.getSvalue(pair);
        uint256 price = data.price;

        return price;
    }

    /**
     * @notice Retrieves the price for a specified pair using the oracle.
     * @dev Emits the PairPrice event on successful retrieval.
     * @param _bytesProof The oracle proof data.
     * @param pair The pair identifier whose price is to be fetched.
     * @return price The price of the specified pair.
     */
    function GetPairPrice(
        bytes calldata _bytesProof,
        uint256 pair
    ) external returns (uint256) {
        ISupraOraclePull.PriceData memory prices = supra_pull.verifyOracleProof(
            _bytesProof
        );
        uint256 price = 0;
        uint256 decimals = 0;
        for (uint256 i = 0; i < prices.pairs.length; i++) {
            if (prices.pairs[i] == pair) {
                price = prices.prices[i];
                decimals = prices.decimals[i];
                emit PairPrice(pair, price, decimals);
                break;
            }
        }
        require(price != 0, "Pair not found");
        return price;
    }

    /**
     * @notice Calculates and updates derived prices from two asset pairs.
     * @param _bytesProof The oracle proof data.
     * @param pair_id_1 The first pair identifier.
     * @param pair_id_2 The second pair identifier.
     * @param operation The operation to perform (0 for multiplication, 1 for division).
     */
    function GetDerivedPairPrice(
        bytes calldata _bytesProof,
        uint256 pair_id_1,
        uint256 pair_id_2,
        uint256 operation
    ) external {
        supra_pull.verifyOracleProof(_bytesProof);
        ISupraSValueFeed.derivedData memory dp = ISupraSValueFeed(supra_storage)
            .getDerivedSvalue(pair_id_1, pair_id_2, operation);
        dPrice = dp.derivedPrice;
        dDecimal = dp.decimals;
        dRound = dp.roundDifference;
    }

    /**
     * @notice Updates the oracle contract address.
     * @param oracle_ The new oracle contract address.
     */
    function updatePullAddress(ISupraOraclePull oracle_) external onlyOwner {
        supra_pull = oracle_;
    }

    /**
     * @notice Updates the storage contract address.
     * @param storage_ The new storage contract address.
     */
    function updateStorageAddress(
        ISupraSValueFeed storage_
    ) external onlyOwner {
        supra_storage = storage_;
    }
}
