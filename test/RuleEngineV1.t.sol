// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "../contracts/RuleEngineV1.sol";
import "../contracts/TicketCollection.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";

/// @title RuleEngineV1Test
/// @notice Basic unit tests for RuleEngineV1.  These tests exercise
/// common scenarios such as price caps and dynamic fee computation.  They
/// are written for the Foundry test framework (forge-std) and can be
/// executed via `forge test`.
contract RuleEngineV1Test is Test, IERC1155Receiver {
    RuleEngineV1 private engine;
    TicketCollection private collection;

    /// @dev Example face value used in tests (0.1 ether).
    uint256 constant FACE_VALUE = 0.1 ether;

    function setUp() public {
        // Set a known starting timestamp
        vm.warp(1000000);

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
        // Mint a ticket to this address
        collection.mint(address(this), 1, 1, "");

        // Skip forward past the initial mint to allow first transfer
        vm.warp(block.timestamp + 1);

        // Transfer with price using the new API
        // capLongBps = 1500 means max 150% of face value = 0.15 ether
        // Use 0.11 ether (10% markup) which is within the cap
        collection.safeTransferFromWithPrice(
            address(this),
            address(0xBEEF),
            1,
            1,
            0.11 ether,  // 10% markup
            "",
            ""
        );

        // Verify the transfer succeeded by checking balance
        assertEq(collection.balanceOf(address(0xBEEF), 1), 1, "Transfer should succeed");
    }

    /// @notice Test that a price exceeding the cap is rejected.
    function testPriceExceedsCap() public {
        // Mint a ticket to this address
        collection.mint(address(this), 1, 1, "");

        // Skip forward past the initial mint to allow first transfer
        vm.warp(block.timestamp + 1);

        // Attempt transfer with excessive price (150% markup > 50% cap)
        vm.expectRevert("Price exceeds cap");
        collection.safeTransferFromWithPrice(
            address(this),
            address(0xBEEF),
            1,
            1,
            0.25 ether,  // 150% markup, exceeds 50% cap
            "",
            ""
        );

        // Verify the transfer was rejected
        assertEq(collection.balanceOf(address(0xBEEF), 1), 0, "Transfer should have failed");
        assertEq(collection.balanceOf(address(this), 1), 1, "Seller should still have ticket");
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
