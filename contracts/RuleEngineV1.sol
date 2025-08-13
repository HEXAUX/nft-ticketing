// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./IRuleEngine.sol";

/// @title RuleEngineV1
/// @notice A configurable rule engine for ticket transfers.  It supports
/// simple price caps and dynamic royalty computation based on how long
/// remains until the event and the markup over face value.  The engine
/// maintains per‑collection parameters and face values for each token ID.
///
/// ## Parameters
/// Each collection has an associated `Params` struct that defines:
///  - `eventTimestamp`: The unix timestamp at which the event starts.
///  - `baseFeeBps`: Base fee applied to all sales (in basis points).
///  - `tLong` and `tMid`: Time thresholds (in seconds).  If the event is
///    further away than `tLong`, the transfer falls into the "long" bucket;
///    if further away than `tMid`, the transfer falls into the "mid" bucket;
///    otherwise it is a "short" sale.  Example: 30 days and 7 days.
///  - `capLongBps` and `capMidBps`: Price cap multiples (in basis
///    points) applied to the face value.  A cap of 1500 means a ticket
///    cannot be sold for more than 1.5× its face value.  For short
///    windows (<= `tMid`) the cap is zero.
///  - `feeLongBps` and `feeMidBps`: Additional fee applied based on
///    remaining time.  For example, if the event is more than 30 days
///    away, add 800 bps; if between 7 and 30 days, add 300 bps; otherwise
///    add nothing.
///  - `markupStepBps`: Size of each markup step in basis points.  A
///    `markupStepBps` of 1000 represents 10% increments over face value.
///  - `markupFeePerStepBps`: Additional fee for each markup step.  For
///    example, 200 bps per 10% markup.  This fee only applies when the
///    sale price exceeds face value.
///  - `maxFeeBps`: Hard cap on the total fee charged.
///
/// Face values are stored per collection and token ID.  Transfers with
/// `priceWei == 0` are treated as gifts and bypass all checks and fees.
contract RuleEngineV1 is IRuleEngine, Ownable {
    /// @dev Parameters for a given ticket collection.
    struct Params {
        uint256 eventTimestamp;
        uint256 baseFeeBps;
        uint256 tLong;
        uint256 tMid;
        uint256 capLongBps;
        uint256 capMidBps;
        uint256 feeLongBps;
        uint256 feeMidBps;
        uint256 markupStepBps;
        uint256 markupFeePerStepBps;
        uint256 maxFeeBps;
    }

    /// @notice Mapping from collection address to parameters.
    mapping(address => Params) public paramsOf;

    /// @notice Face value per collection and token ID (in wei).  Must be
    /// configured by the organiser before sales begin.
    mapping(address => mapping(uint256 => uint256)) public faceValue;

    /// @notice Set parameters for a collection.  Only the owner may call.
    /// @param collection Address of the `TicketCollection` contract.
    /// @param p Parameter struct defining pricing and fee rules.
    function setParams(address collection, Params calldata p) external onlyOwner {
        require(collection != address(0), "RuleEngineV1: invalid collection");
        require(p.eventTimestamp > block.timestamp, "RuleEngineV1: event in past");
        paramsOf[collection] = p;
    }

    /// @notice Set face value for a particular token ID.  Only the owner may call.
    /// @param collection Address of the `TicketCollection` contract.
    /// @param tokenId ERC‑1155 token ID representing a ticket type.
    /// @param priceWei Face value in wei per ticket.
    function setFaceValue(address collection, uint256 tokenId, uint256 priceWei) external onlyOwner {
        require(collection != address(0), "RuleEngineV1: invalid collection");
        faceValue[collection][tokenId] = priceWei;
    }

    /// @inheritdoc IRuleEngine
    function check(TransferCtx calldata ctx)
        external
        view
        override
        returns (bool allowed, uint96 feeBps, string memory reason)
    {
        // Determine the collection address from the caller.  In this
        // implementation the rule engine is called via `TicketCollection.safeTransferFrom`,
        // so `msg.sender` is the collection address.
        address collection = msg.sender;
        Params memory p = paramsOf[collection];

        // If no parameters have been set, allow transfers with zero fee.
        if (p.eventTimestamp == 0) {
            return (true, 0, "");
        }

        // Zero‑price transfers (gifts) always pass through with no fee.
        if (ctx.priceWei == 0) {
            return (true, 0, "");
        }

        // Ensure a face value is defined; otherwise reject.
        uint256 basePrice = faceValue[collection][ctx.tokenId];
        if (basePrice == 0) {
            return (false, 0, "Face value not set");
        }

        // Compute time difference (seconds) until the event.
        if (block.timestamp >= p.eventTimestamp) {
            // Event started or passed; disallow further transfers.
            return (false, 0, "Event already started");
        }
        uint256 delta = p.eventTimestamp - block.timestamp;

        // Determine which bucket applies for cap and time fee.
        uint256 capBps;
        uint256 timeFeeBps;
        if (delta > p.tLong) {
            capBps = p.capLongBps;
            timeFeeBps = p.feeLongBps;
        } else if (delta > p.tMid) {
            capBps = p.capMidBps;
            timeFeeBps = p.feeMidBps;
        } else {
            capBps = 0;
            timeFeeBps = 0;
        }

        // Calculate price per ticket.  Divide priceWei by amount, rounding up.
        // This avoids undercharging markup fees for partial units.
        uint256 pricePer = ctx.priceWei / ctx.amount;

        // Enforce price cap.  If the price per ticket exceeds basePrice * (1 + capBps/10000)
        // then the sale is rejected.
        uint256 maxAllowedPrice = basePrice + (basePrice * capBps) / 10000;
        if (pricePer > maxAllowedPrice) {
            return (false, 0, "Price exceeds cap");
        }

        // Compute markup percentage in basis points.  If pricePer <= basePrice,
        // the markup is zero.
        uint256 markupBps;
        if (pricePer > basePrice) {
            markupBps = ((pricePer - basePrice) * 10000) / basePrice;
        } else {
            markupBps = 0;
        }

        // Compute number of markup steps, each of size `markupStepBps`.
        uint256 steps = p.markupStepBps > 0 ? markupBps / p.markupStepBps : 0;
        uint256 markupFee = steps * p.markupFeePerStepBps;

        // Sum up all fee components.
        uint256 totalFeeBps = p.baseFeeBps + timeFeeBps + markupFee;
        if (totalFeeBps > p.maxFeeBps) {
            totalFeeBps = p.maxFeeBps;
        }

        // All checks passed.
        return (true, uint96(totalFeeBps), "");
    }
}
