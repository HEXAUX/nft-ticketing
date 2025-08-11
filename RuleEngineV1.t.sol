// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "../contracts/RuleEngineV1.sol";
import "../contracts/TicketCollection.sol";

/// @title RuleEngineV1Test
/// @notice Basic unit tests for RuleEngineV1.  These tests exercise
/// common scenarios such as price caps and dynamic fee computation.  They
/// are written for the Foundry test framework (forge-std) and can be
/// executed via `forge test`.
contract RuleEngineV1Test is Test {
    RuleEngineV1 private engine;
    TicketCollection private collection;

    /// @dev Example face value used in tests (0.1 ether).
    uint256 constant FACE_VALUE = 0.1 ether;

    function setUp() public {
        engine = new RuleEngineV1();
        collection = new TicketCollection("Test Event", "uri/{id}", address(this));
        // Configure the rule engine parameters (30 days / 7 days thresholds)
        RuleEngineV1.Params memory p = RuleEngineV1.Params({
            eventTimestamp: block.timestamp + 90 days,
            baseFeeBps: 500,
            tLong: 30 days,
            tMid: 7 days,
            capLongBps: 1500,
            capMidBps: 500,
            feeLongBps: 800,
            feeMidBps: 300,
            markupStepBps: 1000,
            markupFeePerStepBps: 200,
            maxFeeBps: 2500
        });
        engine.setParams(address(collection), p);
        engine.setFaceValue(address(collection), 1, FACE_VALUE);
        collection.setRuleEngine(engine);
    }

    /// @notice Test that a price within the cap passes and computes fees.
    function testLongSaleWithinCap() public {
        // Build a context representing a sale 40 days before the event.
        // priceWei = 0.12 ether (20% markup) for 1 ticket.
        IRuleEngine.TransferCtx memory ctx = IRuleEngine.TransferCtx({
            from: address(this),
            to: address(0xBEEF),
            tokenId: 1,
            amount: 1,
            priceWei: 0.12 ether,
            time: block.timestamp,
            zkRegionProof: "",
            zkAgeProof: ""
        });
        // Event is 90 days away, so this falls into the "long" bucket.
        (bool allowed, uint96 fee, string memory reason) = engine.check(ctx);
        assertTrue(allowed, reason);
        // 20% markup → 2 steps of 10% → markup fee = 2 * 200 = 400 bps.
        // Total = base 500 + time long 800 + markup 400 = 1700 bps.
        assertEq(fee, 1700, "Incorrect fee calculation");
    }

    /// @notice Test that a price exceeding the cap is rejected.
    function testPriceExceedsCap() public {
        // priceWei = 0.25 ether (150% markup) > 1.5x cap → should fail.
        IRuleEngine.TransferCtx memory ctx = IRuleEngine.TransferCtx({
            from: address(this),
            to: address(0xBEEF),
            tokenId: 1,
            amount: 1,
            priceWei: 0.25 ether,
            time: block.timestamp,
            zkRegionProof: "",
            zkAgeProof: ""
        });
        (bool allowed, , string memory reason) = engine.check(ctx);
        assertFalse(allowed, "Transfer should be rejected");
        assertEq(reason, "Price exceeds cap");
    }
}