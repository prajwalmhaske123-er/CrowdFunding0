# CrowdFund — Decentralised Crowdfunding DApp (Project 8)

A decentralised crowdfunding platform built on Ethereum using Solidity smart contracts (Foundry) with a modern web frontend. Creators launch campaigns with funding goals and deadlines; backers contribute ETH; successful campaigns allow creator withdrawal, while failed campaigns enable contributor refunds — all on-chain, trustless, and transparent.

---

## Team Members

| Name    | Roll Number |
| ------- | ----------- |
| Mhaske Prajwal Sanjay | 240004033 |
|Bhumika Kumari | 240051006|
|Shruti Turare | 240008029|
|Malothu Haritha | 240001042|
|Kumkum Kushwaha | 240004028|
|Apoorva Dinesh Chipte | 240021003|

---

## Architecture — On-Chain vs Off-Chain Data

### Stored On-Chain (required for contract logic)
| Data                  | Type                                        |
| --------------------- | ------------------------------------------- |
| Campaign ID           | `uint256` (auto-increment)                  |
| Creator address       | `address`                                   |
| Goal                  | `uint256` (in Wei)                          |
| Deadline              | `uint256` (Unix timestamp)                  |
| Amount raised         | `uint256` (in Wei)                          |
| Status                | `enum (Active, Successful, Failed, FundsWithdrawn)` |
| Contributions mapping | `campaignId → address → uint256`            |
| IPFS CID              | `bytes32` (hash pointer to off-chain data)  |

### Kept Off-Chain (IPFS / server / encrypted store)
- Campaign title, full description, images, pitch video → store on IPFS, put CID on-chain
- Backer reward tiers and fulfilment details
- Creator identity and verification documents (KYC)
- Campaign updates and backer communications

> **Privacy:** Contribution amounts and backer wallet addresses are publicly visible on-chain. Personal details (name, email, shipping address) are **never** stored on-chain.

---

## Tech Stack
- **Smart Contracts:** Solidity ^0.8.24
- **Framework:** Foundry (Forge, Cast, Anvil)
- **Security:** OpenZeppelin ReentrancyGuard
- **Frontend:** HTML, CSS, JavaScript (ethers.js v6)
- **Local Node:** Anvil (Foundry)
---

## Project Structure
```
Crowd-Funding/
├── contract/
│   └── CrowdFunding.sol          # Main smart contract
├── test/
│   └── CrowdFunding.t.sol        # Comprehensive test suite
├── deploy_script/
│   └── deploy.s.sol              # Foundry deployment script
├── frontend/
│   ├── index.html                # DApp frontend
│   ├── styles.css                # Premium dark-mode stylesheet
│   └── app.js                    # Frontend application logic (ABI + MetaMask)
├── reports/
│   ├── gas-report.md             # gas optimization report
│   └── coverage-report.txt       # coverage report
├── lib/
│   ├── forge-std/                # Foundry standard library
│   └── openzeppelin-contracts/   # OpenZeppelin contracts
├── foundry.toml                  # Foundry configuration
└── README.md                     # This file
```

---

## Setup & Installation

### Prerequisites
- [Foundry](https://book.getfoundry.sh/getting-started/installation) installed
- [MetaMask](https://metamask.io/) browser extension
- Git

### 1. Clone & Install Dependencies
```bash
git clone <repository-url>
cd Crowd-Funding

# Install Foundry dependencies (if lib/ is empty)
forge install OpenZeppelin/openzeppelin-contracts --no-commit
```

### 2. Compile
```bash
forge build
```

### 3. Run Tests
```bash
# Run all tests with verbose output
forge test -vvv

# Run tests with gas report
forge test --gas-report

# Run coverage report
forge coverage
```

### 4. Deploy Locally (Anvil)
```bash
# Terminal 1: Start local Ethereum node
anvil

# Terminal 2: Deploy contract
forge script deploy_script/deploy.s.sol:DeployCrowdFunding \
    --rpc-url http://127.0.0.1:8545 \
    --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
    --broadcast
```

> The private key above is the default Anvil account #0 (test only — never use in production).

### 5. Run the Frontend
```bash
# Option A: Use Python's built-in HTTP server
cd frontend
python3 -m http.server 8080

# Option B: Use any static file server
# Then open http://localhost:8080 in your browser
```

### 6. Connect MetaMask to Anvil
1. Open MetaMask → Settings → Networks → Add Network
2. Network Name: `Anvil Local`
3. RPC URL: `http://127.0.0.1:8545`
4. Chain ID: `31337`
5. Currency Symbol: `ETH`
6. Import an Anvil private key for testing

---

## Smart Contract — Key Functions
All public functions have **NatSpec documentation** (`@notice`, `@param`, `@return`).

| Function           | Description                                                 |
| ------------------ | ----------------------------------------------------------- |
| `createCampaign()` | Create a new campaign with goal, duration, and IPFS CID     |
| `contribute()`     | Contribute ETH to an active campaign (payable)              |
| `withdrawFunds()`  | Creator withdraws funds after deadline if goal met          |
| `refund()`         | Contributor claims refund after deadline if goal NOT met    |
| `getCampaign()`    | View function — returns all campaign details                |
| `getContribution()`| View function — returns a contributor's amount for a campaign |

---

## Security Features
- **ReentrancyGuard** (OpenZeppelin) on `withdrawFunds()` and `refund()`
- **Checks-Effects-Interactions** pattern in all state-changing functions
- **Custom errors** for gas-efficient reverts
- **Access control**: only creator can withdraw
- **Deadline enforcement**: no contributions after deadline; no withdrawals before deadline
- **Input validation**: zero-goal, zero-duration, and zero-contribution checks

---

## Testing
The test suite covers:

- ✅ Campaign creation (happy + failure paths)
- ✅ Contributions (single, multiple, edge cases)
- ✅ Successful campaign → creator withdraw → contributors cannot refund
- ✅ Failed campaign → each contributor gets exact refund
- ✅ Creator cannot withdraw before deadline (even if goal met)
- ✅ Contributing after deadline reverts
- ✅ Zero-contribution refund attempt reverts
- ✅ Only creator can withdraw
- ✅ Cannot withdraw/refund twice
- ✅ Event emission verification
- ✅ Non-existent campaign access reverts

Target: **≥ 70% line coverage**

---

## Gas Optimisation
See [gas-report.md](reports/gas-report.md) for detailed before/after analysis.

Key optimisations applied:
1. **Custom errors** instead of `require()` with string messages (~200 gas saved per revert)
2. **`bytes32` for IPFS CID** instead of `string` (saves ~20,000 gas per SSTORE)
3. **`unchecked` block** for safe increment operations
4. **Storage caching** — campaign struct loaded into `storage` pointer to avoid repeated SLOADs

---

## Known Issues / Limitations

- No on-chain campaign search or filtering — requires off-chain indexing (e.g., The Graph).
- No partial/milestone-based withdrawals — creator withdraws full amount in one transaction.
- Campaign metadata relies on IPFS availability; local server fallback provided for development.
- No contribution cap — contributions exceeding the goal are included in the creator's withdrawal (by design, not a vulnerability).
- Single EVM chain deployment only.

---

## License
MIT
