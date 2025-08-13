// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

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

    /// @param _name A human‑friendly name for the collection (e.g. event title).
    /// @param _uri URI template used by ERC‑1155; should include `{id}` to
    ///            point to metadata JSON for each token type.
    /// @param owner Address that will be given ownership of the collection.
    constructor(string memory _name, string memory _uri, address owner)
        ERC1155(_uri)
    {
        name = _name;
        transferOwnership(owner);
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
        // If a rule engine is set, call it to validate the transfer.
        if (address(ruleEngine) != address(0)) {
            // Construct a context.  Note that price and proofs are zeroed
            // here; callers can extend TicketCollection to include these
            // parameters if needed.
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
        super.safeTransferFrom(from, to, id, amount, data);
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
