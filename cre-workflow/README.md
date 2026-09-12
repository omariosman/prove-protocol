# PROVE — Chainlink CRE Verification Workflow

Real Chainlink CRE Confidential Workflow that performs PROVE's core verification step: comparing a task's spec against what the agent actually did on-chain, with the comparison running inside a TEE (Trusted Execution Environment). See `PROVE-hackathon-plan.md` and the root `CLAUDE.md` for the full protocol.

**⚠️ PRIVATE BETA**

[Confidential Workflows](https://docs.chain.link/cre/concepts/confidential-workflows) is in **private beta** and requires enrollment through the Chainlink account team to deploy. This project builds and simulates it — no enrollment needed for that. See "Chainlink prize qualification" below for why simulation is sufficient evidence.

## What it does

1. **Trigger**: an EVM log trigger on `TaskRegistry.ResultSubmitted(uint256 indexed taskId, address indexed agent, bytes32 resultHash)` — fires when an agent submits proof of executing a task.
2. **Public read** (on the Workflow DON, not confidential — it's already public contract state): read the task's spec and `resultHash` from `TaskRegistry.getTask(taskId)`.
3. **Confidential portion** (inside the TEE handler, `handlerInTee`): fetch the agent's actual transaction (`eth_getTransactionByHash` / `eth_getTransactionReceipt`) via a JSON-RPC call made from inside the enclave, then compare it against the task spec — checking recipient, amount, and success status. This is PROVE's verification criteria and the agent's raw execution data: kept confidential from node operators so they can't front-run or game which verifications will pass before the verdict is public.
4. **Cross back to the DON**: only the pass/fail verdict (and `taskId`) cross out of the enclave, encoded into a signed CRE report.

## Chainlink prize qualification

| Requirement | How this meets it |
|---|---|
| CRE Workflow using Confidential Workflows for a meaningful part of the app | `onResultSubmitted` is PROVE's actual verification step, not a demo/placeholder |
| Registers and uses a confidential TEE handler | `cre.handlerInTee(trigger, onResultSubmitted, [{ tee: 'nitro', regions: ['us-west-2'] }])` |
| Processes a sensitive input inside the enclave | The agent's raw transaction data (fetched via confidential HTTP JSON-RPC) and the verification criteria it's compared against — both stay inside the enclave; only the boolean verdict crosses out |
| Meaningfully integrated, not a placeholder | This is the verification engine the whole protocol depends on to release rewards and update trust scores |
| Demonstrated via CRE CLI simulation or live deployment | Simulated against a **real, already-broadcast Sepolia transaction** (see below) — simulation is explicitly accepted per the prize's own qualification text |

## Real simulation evidence

Simulated against `ResultSubmitted` from the actual Task 1.5 Sepolia demo (not a synthetic/mocked event):

```bash
cre workflow simulate verify-task \
  --target staging-settings \
  --non-interactive \
  --trigger-index 0 \
  --evm-tx-hash 0xcf1fe430c68e04be346b13f12ded69404fb750d3550c0bb220ce91a9f740da32 \
  --evm-event-index 0
```

Result: `"Task 1: PASSED (transfer matches spec)"` — matching the real, independently-verified outcome from Task 1.5. Full output captured in `simulation-output.log`.

## Settling the result on-chain

The workflow's verdict is applied via `VerificationOracle.postVerification(taskId, passed, attestation)` — the same `creDON`-gated mechanism already live from Task 1.5, called by a plain script. This is a deliberate choice, not a limitation: delivering a CRE report through Chainlink's own signed-report + `KeystoneForwarder` mechanism would require `VerificationOracle` to implement CRE's `IReceiver` interface, which isn't required by the prize's qualification criteria (simulation evidence is explicitly sufficient) and would add real integration risk for no eligibility benefit. See `CLAUDE.md` for the full reasoning.

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

## Requirements

- CRE CLI (`cre version`), Bun ≥ 1.2.21
- `cre login` (interactive, browser-based) — see the root `CLAUDE.md` for the account setup notes
- `contracts/.env`'s `SEPOLIA_RPC_URL` works fine as the `rpcUrl` config value; no funded wallet needed for simulation (only for `--broadcast`, which this project doesn't use)
