// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/RuleEngineV1.sol";
import "../contracts/TicketCollection.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

/// @dev Simple ERC1155 receiver for testing
contract SimpleReceiver is ERC1155Holder {}

/// @title RuleEngineV1Test
/// @notice Basic unit tests for RuleEngineV1.  These tests exercise
/// common scenarios such as price caps and dynamic fee computation.  They
/// are written for the Foundry test framework (forge-std) and can be
/// executed via `forge test`.
contract RuleEngineV1Test is Test, ERC1155Holder {
    RuleEngineV1 private engine;
    TicketCollection private collection;
    SimpleReceiver private receiver;

    /// @dev Example face value used in tests (0.1 ether).
    uint256 constant FACE_VALUE = 0.1 ether;

    function setUp() public {
        engine = new RuleEngineV1();
        collection = new TicketCollection("Test Event", "uri/{id}", address(this));
        receiver = new SimpleReceiver();
        
        // Configure the rule engine parameters (30 days / 7 days thresholds)
        RuleEngineV1.Params memory p = RuleEngineV1.Params({
            eventTimestamp: block.timestamp + 365 days, // Far in future to avoid time issues
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

    /// @notice Test basic rule engine functionality with direct call
    function testRuleEngineDirectCall() public {
        // Test calling rule engine directly from the collection contract
        // This simulates how the collection would call it
        vm.prank(address(collection));
        IRuleEngine.TransferCtx memory ctx = IRuleEngine.TransferCtx({
            from: address(this),
            to: address(receiver),
            tokenId: 1,
            amount: 1,
            priceWei: 0.11 ether, // 10% markup, within 1.5x cap
            time: block.timestamp,
            zkRegionProof: "",
            zkAgeProof: ""
        });
        
        (bool allowed, uint96 fee, string memory reason) = engine.check(ctx);
        assertTrue(allowed, reason);
        assertGt(fee, 0, "Fee should be greater than 0");
    }

    /// @notice Test that a price exceeding the cap is rejected
    function testPriceExceedsCapDirectCall() public {
        // Test calling rule engine directly from the collection contract
        vm.prank(address(collection));
        IRuleEngine.TransferCtx memory ctx = IRuleEngine.TransferCtx({
            from: address(this),
            to: address(receiver),
            tokenId: 1,
            amount: 1,
            priceWei: 0.25 ether, // 150% markup > 1.5x cap
            time: block.timestamp,
            zkRegionProof: "",
            zkAgeProof: ""
        });
        
        (bool allowed, , string memory reason) = engine.check(ctx);
        assertFalse(allowed, "Transfer should be rejected");
        assertEq(reason, "Price exceeds cap");
    }

    /// @notice Test cooldown functionality
    function testCooldownPeriod() public {
        // Mint a ticket
        collection.mint(address(this), 1, 1, "");
        
        // Verify we have the ticket
        assertEq(collection.balanceOf(address(this), 1), 1);
        
        // Try to transfer immediately (should fail due to 72h cooldown)
        vm.expectRevert("TicketCollection: cooldown 72h");
        collection.safeTransferFrom(address(this), address(receiver), 1, 1, "");
        
        // Skip 72 hours and try again (should succeed)
        vm.warp(block.timestamp + 72 hours + 1);
        
        // Verify we still have the ticket after time warp
        assertEq(collection.balanceOf(address(this), 1), 1, "Should still have ticket after time warp");
        
        collection.safeTransferFrom(address(this), address(receiver), 1, 1, "");
        
        // Verify the transfer succeeded
        assertEq(collection.balanceOf(address(receiver), 1), 1);
        assertEq(collection.balanceOf(address(this), 1), 0);
    }
}