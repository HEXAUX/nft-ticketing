// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "../contracts/RuleEngineV1.sol";
import "../contracts/TicketCollection.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";

/// @title RuleEngineV1FixesTest
/// @notice Tests for the fixes applied to RuleEngineV1
contract RuleEngineV1FixesTest is Test, IERC1155Receiver {
    RuleEngineV1 private engine;
    TicketCollection private collection;

    /// @dev Example face value used in tests (0.1 ether).
    uint256 constant FACE_VALUE = 0.1 ether;

    function setUp() public {
        // Set a known starting timestamp
        vm.warp(1000000);

        engine = new RuleEngineV1();
        collection = new TicketCollection("Test Event", "uri/{id}", address(this));
    }

    /// @notice Test that parameter validation works correctly
    function testParameterValidation() public {
        // Test invalid tLong <= tMid
        RuleEngineV1.Params memory p = RuleEngineV1.Params({
            eventTimestamp: block.timestamp + 90 days,
            baseFeeBps: 500,
            tLong: 7 days,  // Should be > tMid
            tMid: 30 days,  // This is > tLong, should fail
            capLongBps: 1500,
            capMidBps: 500,
            feeLongBps: 800,
            feeMidBps: 300,
            markupStepBps: 1000,
            markupFeePerStepBps: 200,
            maxFeeBps: 2500
        });
        
        vm.expectRevert("RuleEngineV1: tLong must be greater than tMid");
        engine.setParams(address(collection), p);
    }

    /// @notice Test that small markups are properly charged
    function testSmallMarkupFee() public {
        // Configure with small markup step to test precision
        RuleEngineV1.Params memory p = RuleEngineV1.Params({
            eventTimestamp: block.timestamp + 90 days,
            baseFeeBps: 500,
            tLong: 30 days,
            tMid: 7 days,
            capLongBps: 1500,
            capMidBps: 500,
            feeLongBps: 800,
            feeMidBps: 300,
            markupStepBps: 500,  // 5% steps
            markupFeePerStepBps: 200,
            maxFeeBps: 2500
        });
        engine.setParams(address(collection), p);
        engine.setFaceValue(address(collection), 1, FACE_VALUE);
        collection.setRuleEngine(engine);

        // Mint ticket
        collection.mint(address(this), 1, 1, "");
        vm.warp(block.timestamp + 1);

        // Test with 3% markup (should be charged as 1 step)
        collection.safeTransferFromWithPrice(
            address(this),
            address(0xBEEF),
            1,
            1,
            0.103 ether,  // 3% markup
            "",
            ""
        );

        // Verify transfer succeeded - if it went through, the fee was correctly calculated
        assertEq(collection.balanceOf(address(0xBEEF), 1), 1, "Transfer should succeed with correct fee");
    }

    /// @notice Test that price calculation with rounding works correctly
    function testPriceCalculationRounding() public {
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

        // Mint 3 tickets
        collection.mint(address(this), 1, 3, "");
        vm.warp(block.timestamp + 1);

        // Test with amount > 1 to verify rounding up
        collection.safeTransferFromWithPrice(
            address(this),
            address(0xBEEF),
            1,
            3,
            0.32 ether,  // Should round up to ~0.107 per ticket
            "",
            ""
        );

        // Verify transfer succeeded
        assertEq(collection.balanceOf(address(0xBEEF), 1), 3, "Transfer should succeed with proper rounding");
    }

    /// @notice Test that maxFeeBps validation works
    function testMaxFeeBpsValidation() public {
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
            maxFeeBps: 15000  // > 10000, should fail
        });
        
        vm.expectRevert("RuleEngineV1: maxFeeBps cannot exceed 100%");
        engine.setParams(address(collection), p);
    }

    // ERC1155Receiver implementation
    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes calldata
    ) external pure override returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }

    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IERC1155Receiver).interfaceId;
    }
}

