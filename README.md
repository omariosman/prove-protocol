# PROVE — Protocol for AI Agents Reputation and On-chain Verified Execution

Verifies that AI agents actually performed the on-chain tasks they were paid for.
A requester posts a task + reward → an agent executes it on-chain → a Chainlink CRE
Confidential Workflow checks the result against The Graph → reward is released and the
agent's trust score is updated on its ENSv2 identity.

## Structure
| Package | What |
|---|---|
| `contracts/` | Foundry — TaskRegistry, VerificationOracle, AgentRegistry |
| `subgraph/` | The Graph subgraph (verification data source) |
| `cre-workflow/` | Chainlink CRE Confidential Workflow |
| `agent/` | Demo AI-agent executor script |
| `frontend/` | React dashboard |

## Quickstart (contracts)
```bash
cd contracts
cp .env.example .env      # fill in the three values
forge build
forge test
```
