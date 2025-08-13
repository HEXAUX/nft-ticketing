// Basic dApp script for interacting with the NFT ticketing contracts.

let provider;
let signer;

// Connect wallet button
document.getElementById('connect').addEventListener('click', async () => {
    if (window.ethereum) {
        try {
            await window.ethereum.request({ method: 'eth_requestAccounts' });
            provider = new ethers.providers.Web3Provider(window.ethereum);
            signer = provider.getSigner();
            const address = await signer.getAddress();
            document.getElementById('status').innerText = 'Wallet connected: ' + address;
        } catch (err) {
            document.getElementById('status').innerText = 'Error connecting wallet: ' + err.message;
        }
    } else {
        alert('Please install MetaMask to use this demo.');
    }
});

function getContract(address, abi) {
    if (!signer) throw new Error('Wallet not connected');
    return new ethers.Contract(address, abi, signer);
}

// Minimal ABIs for the functions we call
const factoryAbi = [
    'function createTicket(string name, string uri) public returns (address)'
];
const collectionAbi = [
    'function mint(address to, uint256 id, uint256 amount, bytes data) external',
    'function safeTransferFrom(address from, address to, uint256 id, uint256 amount, bytes data) public'
];

// Create a new ticket collection
document.getElementById('createCollection').addEventListener('click', async () => {
    const factoryAddr = document.getElementById('factoryAddr').value.trim();
    const name = document.getElementById('name').value.trim();
    const uri = document.getElementById('uri').value.trim();
    const statusEl = document.getElementById('createStatus');
    if (!factoryAddr || !name || !uri) {
        statusEl.innerText = 'Please fill out all fields.';
        return;
    }
    try {
        const factory = getContract(factoryAddr, factoryAbi);
        const tx = await factory.createTicket(name, uri);
        statusEl.innerText = 'Transaction sent: ' + tx.hash;
        await tx.wait();
        statusEl.innerText = 'Collection created. Tx hash: ' + tx.hash;
    } catch (err) {
        statusEl.innerText = 'Error: ' + err.message;
    }
});

// Mint tickets
document.getElementById('mint').addEventListener('click', async () => {
    const addr = document.getElementById('collectionAddr').value.trim();
    const tokenId = document.getElementById('tokenId').value;
    const amount = document.getElementById('amount').value;
    const statusEl = document.getElementById('mintStatus');
    if (!addr || !tokenId || !amount) {
        statusEl.innerText = 'Please fill out all fields.';
        return;
    }
    try {
        const collection = getContract(addr, collectionAbi);
        const from = await signer.getAddress();
        const tx = await collection.mint(from, tokenId, amount, '0x');
        statusEl.innerText = 'Mint transaction sent: ' + tx.hash;
        await tx.wait();
        statusEl.innerText = 'Mint successful.';
    } catch (err) {
        statusEl.innerText = 'Error: ' + err.message;
    }
});

// Transfer tickets
document.getElementById('transfer').addEventListener('click', async () => {
    const addr = document.getElementById('transferCollectionAddr').value.trim();
    const tokenId = document.getElementById('transferTokenId').value;
    const amount = document.getElementById('transferAmount').value;
    const toAddr = document.getElementById('toAddr').value.trim();
    const statusEl = document.getElementById('transferStatus');
    if (!addr || !tokenId || !amount || !toAddr) {
        statusEl.innerText = 'Please fill out all fields.';
        return;
    }
    try {
        const collection = getContract(addr, collectionAbi);
        const from = await signer.getAddress();
        const tx = await collection.safeTransferFrom(from, toAddr, tokenId, amount, '0x');
        statusEl.innerText = 'Transfer transaction sent: ' + tx.hash;
        await tx.wait();
        statusEl.innerText = 'Transfer successful.';
    } catch (err) {
        statusEl.innerText = 'Error: ' + err.message;
    }
});
