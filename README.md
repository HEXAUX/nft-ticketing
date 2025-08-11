# NFT Ticketing Core Contracts

This repository contains foundational smart contracts and interfaces for a programmable ticketing system.  The goal of this project is to enable "official" secondary sales with configurable rules — such as price caps, cooldown periods and regional/age restrictions — while preventing scalping and protecting user privacy through zero‑knowledge proofs.

The code here is a starting point for a larger system and is intentionally minimal.  You will find three Solidity contracts:

- **`IRuleEngine.sol`** — Defines a `TransferCtx` struct and a single `check` function.  Ticket contracts call the rule engine before each transfer to determine whether a transfer is allowed and what royalty (if any) should be charged.
- **`TicketCollection.sol`** — An ERC‑1155 NFT representing a collection of tickets for a single event.  The owner can mint new tickets and set a rule engine.  Transfers invoke the rule engine to enforce resale rules, and the contract supports a simple `checkIn` function for marking tickets as used.
- **`TicketFactory.sol`** — A factory that deploys new `TicketCollection` instances.  This allows event organisers to spin up a fresh collection for each event without manually deploying the ticket contract themselves.

These contracts are intended for demonstration and development purposes only.  They omit many production features such as on‑chain storage of verifying keys, dynamic royalty logic, and integration with account abstraction wallets.  For more information about the overall architecture and design rationale, please refer to the project documentation and technical blueprint.

## Usage

1. Deploy `TicketFactory` on an EVM‑compatible network.
2. Call `createTicket(name, uri)` to deploy a new `TicketCollection` for an event.  The caller becomes the owner of the collection.
3. Mint tickets via `TicketCollection.mint()` and distribute them to buyers.
4. Implement a contract that conforms to `IRuleEngine` and set it on your `TicketCollection` instance via `setRuleEngine()`.  The rule engine can enforce cooldowns, price caps, age/region proofs, and calculate royalties.

This code uses Solidity ^0.8.17 and assumes that OpenZeppelin's contracts are available at compile time.  You will need a Solidity development environment such as Hardhat or Foundry to compile and test these contracts.