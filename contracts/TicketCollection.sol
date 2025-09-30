// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./IRuleEngine.sol";

/// @title TicketCollection
/// @notice ERC‑1155 ticket collection with pluggable rule enforcement.  The owner
/// (e.g. event organiser) can mint new tickets, set a rule engine and mark
/// tickets as used via `checkIn`.  Transfers are subject to the rule engine
/// when set.
contract TicketCollection is ERC1155, Ownable {
    /// @notice Descriptive name for the collection (not part of ERC‑1155)
    string public name;

    /// @notice Optional rule engine contract that enforces transfer rules.
    IRuleEngine public ruleEngine;

    /// @dev Track which tickets have been checked in by holder and token ID.
    mapping(address => mapping(uint256 => bool)) public checkedIn;

    /// @dev Timestamp of the last transfer or mint for each holder and token ID.
    /// Used to enforce per‑ticket cooldowns on subsequent transfers.
    mapping(address => mapping(uint256 => uint256)) public lastTransferTime;

    /// @dev Flag indicating whether the next transfer for a holder/tokenId pair
    /// will be treated as the first resale after mint.  When true, a 72‑hour
    /// cooldown is applied; otherwise a 24‑hour cooldown applies.  This flag
    /// is set on mint and cleared after the first transfer.
    mapping(address => mapping(uint256 => bool)) public firstTransferPending;

    /// @param _name A human‑friendly name for the collection (e.g. event title).
    /// @param _uri URI template used by ERC‑1155; should include `{id}` to
    ///            point to metadata JSON for each token type.
    /// @param owner Address that will be given ownership of the collection.
    constructor(string memory _name, string memory _uri, address owner)
        ERC1155(_uri)
        Ownable(owner)
    {
        name = _name;
    }

    /// @notice Set the rule engine contract.  Only callable by the owner.
    function setRuleEngine(IRuleEngine engine) external onlyOwner {
        ruleEngine = engine;
    }

    /// @notice Mint new tickets.  Only callable by the owner.
    function mint(
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) external onlyOwner {
        _mint(to, id, amount, data);
    }

    /// @dev Event emitted when a transfer with price is executed.
    event TransferWithPrice(
        address indexed from,
        address indexed to,
        uint256 indexed tokenId,
        uint256 amount,
        uint256 priceWei,
        uint256 feeBps
    );

    /// @notice Transfer tickets with price information for rule engine validation.
    /// @param from Sender address.
    /// @param to Recipient address.
    /// @param id Token ID.
    /// @param amount Number of tickets.
    /// @param priceWei Total price in wei (0 for gifts).
    /// @param zkRegionProof Zero-knowledge proof for region eligibility.
    /// @param zkAgeProof Zero-knowledge proof for age eligibility.
    function safeTransferFromWithPrice(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        uint256 priceWei,
        bytes memory zkRegionProof,
        bytes memory zkAgeProof
    ) public virtual {
        // Store price information in storage for _update to access
        _pendingTransfer = IRuleEngine.TransferCtx({
            from: from,
            to: to,
            tokenId: id,
            amount: amount,
            priceWei: priceWei,
            time: block.timestamp,
            zkRegionProof: zkRegionProof,
            zkAgeProof: zkAgeProof
        });
        _hasPendingTransfer = true;

        // Execute the transfer
        safeTransferFrom(from, to, id, amount, "");

        // Clear pending transfer
        _hasPendingTransfer = false;
        delete _pendingTransfer;
    }

    /// @inheritdoc ERC1155
    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) public virtual override {
        super.safeTransferFrom(from, to, id, amount, data);
    }

    /// @dev Storage for pending transfer context during safeTransferFromWithPrice
    IRuleEngine.TransferCtx private _pendingTransfer;
    bool private _hasPendingTransfer;

    /// @inheritdoc ERC1155
    function _update(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory values
    ) internal virtual override {
        super._update(from, to, ids, values);

        // Handle mint: mark first transfer pending but don't set lastTransferTime yet.
        // This ensures the 72h cooldown starts from the first transfer, not mint.
        if (from == address(0)) {
            for (uint256 i = 0; i < ids.length; i++) {
                uint256 id = ids[i];
                firstTransferPending[to][id] = true;
            }
            return;
        }

        // Handle burn: nothing to enforce on burns.
        if (to == address(0)) {
            return;
        }

        // For each token being transferred, enforce cooldown and rule engine check.
        for (uint256 i = 0; i < ids.length; i++) {
            uint256 id = ids[i];
            uint256 amount = values[i];

            // Enforce cooldown based on whether this is the first resale.
            uint256 lastTime = lastTransferTime[from][id];
            if (lastTime > 0) {  // Skip cooldown check if never transferred (first transfer)
                uint256 required;
                if (firstTransferPending[from][id]) {
                    required = 72 hours;
                } else {
                    required = 24 hours;
                }
                require(
                    block.timestamp >= lastTime + required,
                    firstTransferPending[from][id]
                        ? "TicketCollection: cooldown 72h"
                        : "TicketCollection: cooldown 24h"
                );
            }

            // If a rule engine is set, validate the transfer.
            uint96 feeBps = 0;
            if (address(ruleEngine) != address(0)) {
                IRuleEngine.TransferCtx memory ctx;

                // Use pending transfer context if available (from safeTransferFromWithPrice)
                if (_hasPendingTransfer && _pendingTransfer.tokenId == id) {
                    ctx = _pendingTransfer;
                } else {
                    // Fallback: treat as gift transfer (priceWei = 0)
                    ctx = IRuleEngine.TransferCtx({
                        from: from,
                        to: to,
                        tokenId: id,
                        amount: amount,
                        priceWei: 0,
                        time: block.timestamp,
                        zkRegionProof: "",
                        zkAgeProof: ""
                    });
                }

                (bool allowed, uint96 fee, string memory reason) = ruleEngine.check(ctx);
                require(allowed, reason);
                feeBps = fee;

                // Emit event if price is set
                if (ctx.priceWei > 0) {
                    emit TransferWithPrice(from, to, id, amount, ctx.priceWei, feeBps);
                }
            }

            // Update state for the recipient to enforce 24h cooldown going forward.
            lastTransferTime[to][id] = block.timestamp;
            firstTransferPending[to][id] = false;
        }
    }

    /// @dev Event emitted when a ticket is checked in.
    event CheckedIn(address indexed holder, uint256 indexed tokenId);

    /// @notice Mark a ticket as used. The caller must hold the ticket.
    /// Each holder can check in their own ticket independently.
    /// @param id Token ID to check in.
    function checkIn(uint256 id) external {
        require(balanceOf(msg.sender, id) > 0, "TicketCollection: not holder");
        require(!checkedIn[msg.sender][id], "TicketCollection: already checked in");
        checkedIn[msg.sender][id] = true;
        emit CheckedIn(msg.sender, id);
    }
}
