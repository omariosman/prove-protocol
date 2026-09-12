# PROVE — Chainlink CRE Verification Workflow

## What it does

1. **Trigger**: an EVM log trigger on `TaskRegistry.ResultSubmitted(uint256 indexed taskId, address indexed agent, bytes32 resultHash)` — fires when an agent submits proof of executing a task.
2. **Public read** (on the Workflow DON, not confidential — it's already public contract state): read the task's spec and `resultHash` from `TaskRegistry.getTask(taskId)`.
3. **Confidential portion** (inside the TEE handler, `handlerInTee`): fetch the agent's actual transaction (`eth_getTransactionByHash` / `eth_getTransactionReceipt`) via a JSON-RPC call made from inside the enclave, then compare it against the task spec — checking recipient, amount, and success status. This is PROVE's verification criteria and the agent's raw execution data: kept confidential from node operators so they can't front-run or game which verifications will pass before the verdict is public.


## Simulation

Simulated against `ResultSubmitted` from Sepolia demo:

```bash
cre workflow simulate verify-task \
  --target staging-settings \
  --non-interactive \
  --trigger-index 0 \
  --evm-tx-hash 0xcf1fe430c68e04be346b13f12ded69404fb750d3550c0bb220ce91a9f740da32 \
  --evm-event-index 0
```

Result: `"Task 1: PASSED (transfer matches spec)"` — Full output captured in `simulation-output.log`.

## Project structure

```
cre-workflow/
├── verify-task/
│   ├── workflow.ts          # trigger + TEE handler + verification logic
│   ├── workflow.test.ts     # unit tests for verifyTransferSpec + initWorkflow
│   ├── main.ts               # entry point
│   ├── config.staging.json   # TaskRegistry address, chain, RPC URL
│   └── workflow.yaml
├── project.yaml               # RPC endpoints
├── secrets.yaml                # empty - no Vault DON secrets needed
└── simulation-output.log       # captured evidence from the real simulation above
```

## Commands

```bash
# from cre-workflow/verify-task/
bun install
bunx cre-setup      # WASM tooling, usually run automatically by postinstall
bunx tsc --noEmit    # typecheck
bun test             # unit tests

# from cre-workflow/ (project root)
cre workflow simulate verify-task --target staging-settings \
  --non-interactive --trigger-index 0 \
  --evm-tx-hash <tx-hash-with-a-ResultSubmitted-log> --evm-event-index 0
```
