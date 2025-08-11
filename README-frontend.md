## NFT Ticketing Frontend Demo

This folder contains a small demonstration DApp for the NFT ticketing system. The goal of this frontend is to provide an attractive, Web3‑inspired interface that showcases the core workflows for creating, minting and transferring NFT tickets.

### Features

- **Modern UI**: A dynamic gradient background, glassmorphism panels and neon buttons give the page a polished and futuristic feel without relying on additional design libraries. Styling is handled via Tailwind CSS plus a few custom CSS rules.
- **Wallet connection**: Users can connect with MetaMask or any Ethereum provider via `ethers.js`. The connection status is displayed on the page.
- **Create a collection**: Input your deployed `TicketFactory` contract address along with a name and a URI template to create a new ticket collection. The contract emits a `CollectionCreated` event and the UI displays the resulting collection address.
- **Mint tickets**: Use a collection address, token ID and amount to mint tickets to your own wallet. The UI reports transaction hashes and status.
- **Transfer tickets**: Enter the collection address, token ID, amount, and recipient to transfer tickets from your connected wallet. Transaction status messages are displayed.

### Usage

To run the demo locally:

1. Ensure you have a modern browser with a Web3 wallet extension such as MetaMask installed.
2. Serve the `index.html` file via a local web server (for example, using Python's `http.server`) or by opening it directly if your browser allows reading local scripts.
3. Deploy the backend contracts (`TicketFactory.sol` and `TicketCollection.sol`) to an Ethereum testnet or local chain. Replace the example addresses in the form fields accordingly.
4. Open the page and click **Connect Wallet**. After your wallet is connected, you will see your address in the status panel.
5. Use the **Create Ticket Collection** section to deploy a new collection. Provide the factory contract address, a name and a URI template. Once the transaction confirms, the created collection address appears.
6. Use the **Mint Ticket** section to mint tokens to your wallet. Enter the collection address, the token ID and the amount you wish to mint.
7. Use the **Transfer Ticket** section to send tickets to another address. Provide the collection address, token ID, amount and the recipient's wallet address.

This demo is intentionally minimal but can be extended with additional logic for rules, royalties and zero‑knowledge proof interactions as the broader project evolves.