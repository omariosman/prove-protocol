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

For a task with real uncertainty (e.g. an unfamiliar external integration), split it into an **epic issue + sub-issues** instead of one issue: epic has a `- [ ] #n` checklist linking each sub-issue, each sub-issue gets its own branch/PR/merge following steps 2–6 above, sub-issues get a "Part of epic #n" comment. See Task 1.4 (epic [#6](https://github.com/omariosman/prove-protocol/issues/6): [#3](https://github.com/omariosman/prove-protocol/issues/3)/[#4](https://github.com/omariosman/prove-protocol/issues/4)/[#5](https://github.com/omariosman/prove-protocol/issues/5)) for the pattern.

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
  - **Task 1.4a done** (branch `task-1.4a-agent-registry-core`, issue [#3](https://github.com/omariosman/prove-protocol/issues/3), epic [#6](https://github.com/omariosman/prove-protocol/issues/6)): `src/AgentRegistry.sol` + `src/IAgentRegistry.sol` + 11 passing tests (`test/AgentRegistry.t.sol`), plus `VerificationOracle`'s `TODO(Task 1.4)` replaced with a real call. Notes:
    - Agents get **sequential labels** (`agent1`, `agent2`, ...); `ensNode = keccak256(bytes("agent<N>.prove.eth"))` is a **placeholder key**, not a real ENS namehash, until #4/#5 mint the actual subname. `Agent.ensName` stores the human-readable string for when that happens.
    - `registerAgent` is owner-only (no open registration in the PoC).
    - `recordResult(ensNode, passed)` gated by a single `scoreUpdater` address (same pattern as `TaskRegistry.verificationOracle` / `VerificationOracle.creDON`), set to `VerificationOracle`.
    - `trustScore` returns a wad (1e18 = 100%), 0 if the agent has no tasks yet.
    - `VerificationOracle.postVerification` now requires `agentRegistry != address(0)` and calls `IAgentRegistry(agentRegistry).recordResult(agentENSNode, passed)` using the `agentENSNode` stored on the task (`TaskRegistry.getTask(taskId)`) — the caller of `createTask` must pass the exact `ensNode` an agent was registered with.
    - `script/Deploy.s.sol` deploys `AgentRegistry` and wires `oracle.setAgentRegistry` + `agentRegistry.setScoreUpdater`. Per-agent ENS registration is a separate script (`script/RegisterAgentENS.s.sol`, issue #4), not part of base deploy.
  - **Task 1.4b/1.4c not started** (issues [#4](https://github.com/omariosman/prove-protocol/issues/4)/[#5](https://github.com/omariosman/prove-protocol/issues/5)): real ENSv2 registration of `prove.eth` + agent subnames on Sepolia, then wiring `AgentRegistry` to write real text records. See "ENSv2 integration notes" below before starting.
- `subgraph/` — The Graph (not created yet, Task 2.1)
- `cre-workflow/` — TypeScript CRE workflow (Task 2.2)
- `agent/` — Node.js/ethers executor script (Task 2.3)
- `frontend/` — React + wagmi + viem + ensjs (Task 3.1)

## ENSv2 integration notes (for Task 1.4b/1.4c)

ENSv2 is beta, live on Sepolia, source at `ensdomains/contracts-v2` on GitHub (actively pushed to as of Sep 2026 — check for drift before relying on old notes here). **Verified 2026-09-12** by pulling deployment JSON + contract source directly via `gh api` (raw bytes, not a summarized fetch) — a prior attempt using a page-summarizing web fetch returned fabricated contract addresses. Don't trust ENSv2 addresses/interfaces from a summarized source; get them from `contracts/deployments/sepolia/*.json` or contract source in that repo, or a live on-chain read.

- Registration is priced only in stablecoins (no ETH/oracle path) — on Sepolia that's `MockUSDC`/`MockDAI`, both freely mintable via `mint(address,uint256)` (no access control). No real funds needed.
- Access control is **Enhanced Access Control (EAC)**: bitmap-packed roles scoped per-resource (`uint256 resource`, e.g. a namehash or `resource(node, part)` for a specific text-record key), not OpenZeppelin's flat `AccessControl`. Roles are granted via `grantRoles(resource, roleBitmap, account)`; `ROLE_REGISTRAR`/`ROLE_SET_TEXT`/etc. are defined in `RegistryRolesLib`/`PermissionedResolverLib`.
- To mint a subname you need a `PermissionedRegistry` you control (deployed via `VerifiableFactory`) set as the parent name's subregistry — `prove.eth` needs one deployed before subnames can be minted under it.
- Verified Sepolia addresses (subject to redeploys — re-verify against the source above if anything reverts unexpectedly):

  | Contract | Address |
  |---|---|
  | ETHRegistrar | `0xa4449a0dd2b83007553d9b1d28b583a46a805a30` |
  | RootRegistry | `0x11b5bfbe9078d826b1edbdd1cfc12f5828d9f50c` |
  | VerifiableFactory | `0x118bc31a50d559f7015a8da26d54b3b030cdb70f` |
  | PermissionedResolverImpl | `0x7e4b2d59938930168024201752ee5503df402303` |
  | LabelStore | `0xb03524289c16424f71802a1794c29c7bd1b9f577` |
  | MockUSDC | `0xd3322b29a7bdee707d1684676f149bf41aa3422f` |
  | MockDAI | `0xe33a01a41ee4a68616b5278183aa88808326ed8e` |

- Full step-by-step registration flow is in issue [#4](https://github.com/omariosman/prove-protocol/issues/4).

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
