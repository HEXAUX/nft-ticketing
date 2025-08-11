// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./TicketCollection.sol";

/// @title TicketFactory
/// @notice Deploys new ticket collections for events.  This factory keeps a
/// registry of all collections created by each caller and emits an event on
/// creation.  Event organisers can use the factory to create a fresh
/// `TicketCollection` for each performance or tour without writing Solidity.
contract TicketFactory {
    /// @notice Emitted when a new ticket collection is created.
    /// @param operator Address that called `createTicket`.
    /// @param ticketCollection Address of the newly deployed `TicketCollection`.
    /// @param name Name of the event/collection.
    event TicketCreated(address indexed operator, address ticketCollection, string name);

    /// @notice List of collections created by each creator.
    mapping(address => address[]) public ticketsByCreator;

    /// @notice Deploy a new ticket collection.
    /// @param name Human‑readable name for the collection (e.g. event title).
    /// @param uri ERC‑1155 URI template for metadata (should include `{id}`).
    /// @return collection Address of the newly deployed `TicketCollection`.
    function createTicket(string memory name, string memory uri)
        external
        returns (address collection)
    {
        TicketCollection ticket = new TicketCollection(name, uri, msg.sender);
        ticketsByCreator[msg.sender].push(address(ticket));
        emit TicketCreated(msg.sender, address(ticket), name);
        return address(ticket);
    }
}