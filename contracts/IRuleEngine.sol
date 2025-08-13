// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/// @title IRuleEngine
/// @notice Interface for pluggable rule engines used by ticket collections.  A rule
/// engine decides whether a given transfer is allowed and may impose a fee.
interface IRuleEngine {
    /// @notice Context passed to the rule engine for each attempted transfer.
    /// Implementations can extend this struct in a backward‑compatible way by
    /// encoding additional fields in the `data` parameters.
    struct TransferCtx {
        address from;
        address to;
        uint256 tokenId;
        uint256 amount;
        uint256 priceWei;      // sale price denominated in wei (0 for free transfers)
        uint256 time;           // timestamp of the transfer attempt
        bytes zkRegionProof;    // zero‑knowledge proof of region eligibility
        bytes zkAgeProof;       // zero‑knowledge proof of age eligibility
    }

    /// @notice Perform checks on a ticket transfer.  Rule engines MUST NOT
    /// mutate state; they should be pure/view functions that throw or return
    /// an error when transfers are not allowed.
    /// @param ctx Transfer context containing sender, receiver, token and price.
    /// @return allowed Whether the transfer is permitted.
    /// @return feeBps The royalty fee in basis points (1/10,000 of the sale price).
    /// @return reason A human‑readable reason for rejection when `allowed` is false.
    function check(TransferCtx calldata ctx)
        external
        view
        returns (bool allowed, uint96 feeBps, string memory reason);
}
