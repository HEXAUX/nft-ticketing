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

    /// @dev Track which ticket IDs have been checked in (used).
    mapping(uint256 => bool) public checkedIn;

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

    /// @notice Transfer with price information for rule engine validation
    /// @dev This function should be used by marketplaces to provide price context
    function safeTransferFromWithPrice(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        uint256 priceWei,
        bytes memory zkRegionProof,
        bytes memory zkAgeProof,
        bytes memory data
    ) external {
        require(
            from == msg.sender || isApprovedForAll(from, msg.sender),
            "TicketCollection: caller is not owner nor approved"
        );

        // Validate with rule engine if set
        if (address(ruleEngine) != address(0)) {
            IRuleEngine.TransferCtx memory ctx = IRuleEngine.TransferCtx({
                from: from,
                to: to,
                tokenId: id,
                amount: amount,
                priceWei: priceWei,
                time: block.timestamp,
                zkRegionProof: zkRegionProof,
                zkAgeProof: zkAgeProof
            });
            (bool allowed, , string memory reason) = ruleEngine.check(ctx);
            require(allowed, reason);
        }

        // Perform the transfer
        _safeTransferFrom(from, to, id, amount, data);
    }

    /// @dev Hook called before any token transfer
    function _update(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory values
    ) internal virtual override {

        // Handle mint: record mint time and mark first transfer pending.
        if (from == address(0)) {
            for (uint256 i = 0; i < ids.length; i++) {
                uint256 id = ids[i];
                // Record the time of mint for the recipient.
                lastTransferTime[to][id] = block.timestamp;
                firstTransferPending[to][id] = true;
            }
            // Call parent implementation for mint
            super._update(from, to, ids, values);
            return;
        }

        // Handle burn: nothing to enforce on burns.
        if (to == address(0)) {
            // Call parent implementation for burn
            super._update(from, to, ids, values);
            return;
        }

        // For each token being transferred, enforce cooldown and rule engine check.
        for (uint256 i = 0; i < ids.length; i++) {
            uint256 id = ids[i];
            uint256 amount = values[i];

            // Enforce cooldown based on whether this is the first resale.
            uint256 lastTime = lastTransferTime[from][id];
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

            // If a rule engine is set, validate the transfer.  Price and proofs
            // are zeroed here; marketplace or frontends should supply these
            // parameters as needed.
            if (address(ruleEngine) != address(0)) {
                IRuleEngine.TransferCtx memory ctx = IRuleEngine.TransferCtx({
                    from: from,
                    to: to,
                    tokenId: id,
                    amount: amount,
                    priceWei: 0,
                    time: block.timestamp,
                    zkRegionProof: "",
                    zkAgeProof: ""
                });
                (bool allowed, , string memory reason) = ruleEngine.check(ctx);
                require(allowed, reason);
            }

            // Update state for the recipient to enforce 24h cooldown going forward.
            lastTransferTime[to][id] = block.timestamp;
            firstTransferPending[to][id] = false;
            // Clear first transfer flag for the sender to avoid unnecessary
            // 72h cooldown checks for subsequent transfers.
            firstTransferPending[from][id] = false;
        }
        
        // Call parent implementation
        super._update(from, to, ids, values);
    }

    /// @notice Mark a ticket as used.  The caller must hold the ticket.
    /// This basic implementation simply records that the given `id` has
    /// been checked in.  A more robust implementation would tie this state
    /// to individual token holders or support multi‑use tickets.
    function checkIn(uint256 id, bytes memory data) external {
        require(balanceOf(msg.sender, id) > 0, "TicketCollection: not holder");
        require(!checkedIn[id], "TicketCollection: already checked in");
        checkedIn[id] = true;
        // data parameter is unused but included for extensibility.
    }
}
