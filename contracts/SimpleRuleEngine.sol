// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./IRuleEngine.sol";

/// @title SimpleRuleEngine
/// @notice A minimal example implementation of the `IRuleEngine` interface.  This
/// rule engine accepts all transfers and does not impose any fees.  It is
/// intended for demonstration and testing purposes.  A real rule engine would
/// implement price caps, cooldown periods, dynamic royalties and
/// zero‑knowledge proof validation.
contract SimpleRuleEngine is IRuleEngine {
    /// @inheritdoc IRuleEngine
    function check(TransferCtx calldata /*ctx*/)
        external
        pure
        override
        returns (bool allowed, uint96 feeBps, string memory reason)
    {
        // Always allow transfers with zero fee.  A real implementation could
        // inspect `ctx.priceWei`, `ctx.time` or ZK proofs to decide whether
        // to allow the transfer and what fee to charge.
        allowed = true;
        feeBps = 0;
        reason = "";
    }
}
