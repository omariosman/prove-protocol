# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Name

**PROVE** — Protocol for Reputation and On-chain Verified Execution. (Formerly "VAEL" in early drafts — use **PROVE** / `prove` everywhere: contract names, ENS parent `prove.eth`, text-record keys `com.prove.*`, subgraph slug `prove-subgraph`, package names.)

This is a **hackathon proof-of-concept** for ETH Online 2026, not production software. Bias hard toward the simplest thing that demonstrates the flow end-to-end. No premature abstraction, no extra features, minimal dependencies. `PROVE-hackathon-plan.md` is the source of truth for scope — read it before starting a task.

## Working Style

- Execute the plan one task at a time (Task 1.1, 1.2, …). After finishing each task, stop and report: what was done + exactly how the user can test it. Wait for confirmation before the next task.
- Ask the user for anything you can't self-serve (RPC URLs, API keys, funded test wallets, deployed addresses).

### Git/GitHub workflow (from Task 1.3 onward)

Repo: `omariosman/prove-protocol` (`gh` CLI installed at `~/.local/bin/gh`, authenticated as `omariosman`). Tasks 1.1–1.2 went straight to `main`; everything after follows this flow:

1. **Issue first** — before writing code, `gh issue create` documenting the task's scope (what plan section, what's in/out, definition of done). One issue per plan task (e.g. "Task 1.3: VerificationOracle.sol").
2. **Branch per task** — `git checkout -b task-<n>-<slug>` off `main`, named after the issue.
3. **Implement + test locally** — build/test on the branch. Update `CLAUDE.md`'s Repo Layout section with what was done and any deviations, same as before.
4. **Wait for the user to test and confirm** before opening a PR — do not open the PR until they say it's good.
5. **PR** referencing the issue (`Closes #<n>` in the PR body) so merging auto-closes it. Commit messages also mention the issue number.
6. Merge only on explicit user go-ahead.

## What PROVE Is

End-to-end flow, and why each piece exists:

1. Requester calls `TaskRegistry.createTask(agentENSNode, taskSpec, reward)` and deposits ETH/ERC20. Task specs are simple JSON (`{"type":"transfer","token":"ETH","amount":"0.01","to":"0x..","deadline":..}`).
2. An off-chain agent script watches `TaskCreated`, executes the on-chain action, then calls `TaskRegistry.submitResult(taskId, resultHash)`.
3. `ResultSubmitted` triggers a **Chainlink CRE Confidential Workflow** (TEE). It reads the task spec on-chain, queries **The Graph subgraph** for what the agent actually did, compares spec vs. reality, and produces a pass/fail attestation.
4. The CRE DON calls `VerificationOracle.postVerification(taskId, passed, attestation)`. Pass → `TaskRegistry` releases reward + `AgentRegistry` bumps trust score. Fail → refund requester + penalize score.
5. Trust score / task counts live as ENSv2 text records (`com.prove.trustScore`, `com.prove.totalTasks`) on the agent's subname (`agent1.prove.eth` under `prove.eth`).

The Graph is the **verification data source**, not a cosmetic index — the CRE workflow depends on it. It's a judged prize criterion; keep it central.

## Architecture Constraints

- **Network is Ethereum Sepolia**, non-negotiable (ENSv2 requirement).
- **Access-control boundaries** that must hold across contracts:
  - Only the CRE DON address may call `VerificationOracle.postVerification`.
  - Only `VerificationOracle` may update trust scores (`SCORE_UPDATER`).
  - Reward release/refund in `TaskRegistry` is internal, reachable only via the verification path.
- **Task status is one enum** threaded through all layers: `Open → Executed → Verified → Paid` or `Failed`. Keep the string values identical between Solidity events and the subgraph `schema.graphql`.
- **Fallbacks are intentional** (plan §8): if CRE deployment fails, a script running the same verification logic off-chain and posting to `VerificationOracle` is acceptable. If ENSv2 beta breaks, a mock contract with the same interface is acceptable. Don't redesign to avoid these dependencies — document the intended integration and use the fallback.

## Repo Layout

Monorepo, independent packages:
- `contracts/` — Foundry project. OZ v5 + forge-std; `foundry.toml` has Sepolia RPC + Etherscan via env vars; solc 0.8.28.
  - **Task 1.1 done**: scaffolding, `.env.example`.
  - **Task 1.2 done**: `src/TaskRegistry.sol` + 15 passing tests (`test/TaskRegistry.t.sol`). Deviations from the plan, all for PoC simplicity:
    - ETH-only rewards. `createTask(bytes32 agentENSNode, string taskSpec, uint256 deadline)` — reward is `msg.value` (the plan's `uint256 reward` param is dropped).
    - `resultHash` is `bytes32`, not `bytes`.
    - Oracle entrypoint is `completeTask(uint256 taskId, bool passed)` (guarded by `verificationOracle` address, set once by owner via `setVerificationOracle`). It calls internal `_releaseReward` / `_refundReward`.
    - `taskSpec` JSON is stored on-chain as a string so the CRE workflow can read it directly.
    - Added `reclaimExpired(taskId)` so an Open task past its deadline can be refunded (avoids stuck ETH).
    - Status flow in practice: `Open -> Executed -> Verified -> Paid` (pass) or `-> Failed` (fail / expiry).
  - **Task 1.3 done** (branch `task-1.3-verification-oracle`, issue [#1](https://github.com/omariosman/prove-protocol/issues/1)): `src/VerificationOracle.sol` + 12 passing tests (`test/VerificationOracle.t.sol`). Notes:
    - `postVerification(taskId, passed, attestation)` gated by a single `creDON` address (owner-settable) — stands in for the CRE DON per the plan's documented fallback (a trusted script instead of a real DON).
    - Calls `TaskRegistry.completeTask`, which already guards against re-verifying a task not in `Executed` state — no separate double-verification check needed.
    - `agentRegistry` address + `setAgentRegistry` are stubbed (`address(0)`) until Task 1.4; the trust-score update is a `TODO(Task 1.4)` comment, not yet wired.
    - `script/Deploy.s.sol` now deploys `TaskRegistry` + `VerificationOracle` and wires `setVerificationOracle`; `CRE_DON_ADDRESS` env var is optional (defaults to deployer). Actual Sepolia deployment still deferred until Task 1.4 lands so it's one combined deploy.
- `subgraph/` — The Graph (not created yet, Task 2.1)
- `cre-workflow/` — TypeScript CRE workflow (Task 2.2)
- `agent/` — Node.js/ethers executor script (Task 2.3)
- `frontend/` — React + wagmi + viem + ensjs (Task 3.1)

## Commands

**contracts/** (run from `contracts/`):
```bash
forge build
forge test
forge test --match-test <name> -vvv        # single test
forge test --match-contract TaskRegistryTest # single test file
cp .env.example .env                         # then fill PRIVATE_KEY, SEPOLIA_RPC_URL, ETHERSCAN_API_KEY
forge script script/Deploy.s.sol --rpc-url sepolia --broadcast --verify
```

Other packages: standard `npm install` + package `scripts` once they exist.

## Priority Order (if short on time)

TaskRegistry + VerificationOracle → subgraph → AgentRegistry/ENSv2 → CRE workflow (simulation OK) → agent script → frontend. Always reserve time for the demo video — required for all three prize tracks.
