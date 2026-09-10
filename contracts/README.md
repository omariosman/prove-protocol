# PROVE — Contracts

Foundry project for the PROVE protocol (Protocol for Reputation and On-chain Verified Execution).

## Contracts (built across Tasks 1.2–1.4)
- `TaskRegistry.sol` — task creation, result submission, reward escrow
- `VerificationOracle.sol` — receives pass/fail attestations, releases/refunds rewards
- `AgentRegistry.sol` — agent identity + trust score (ENSv2 on Sepolia, mock fallback)

## Commands
```bash
forge build
forge test                 # all tests
forge test --match-test <name> -vvv
forge test --match-contract TaskRegistryTest

# deploy (needs contracts/.env — copy from .env.example)
forge script script/Deploy.s.sol --rpc-url sepolia --broadcast --verify
```

## Setup
```bash
cp .env.example .env   # then fill in PRIVATE_KEY, SEPOLIA_RPC_URL, ETHERSCAN_API_KEY
```
