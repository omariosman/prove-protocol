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
3. `ResultSubmitted` triggers a **Chainlink CRE Confidential Workflow** (TEE). It reads the task spec on-chain and verifies the agent's action directly via RPC (checks the `resultHash` tx receipt/logs against the spec), then produces a pass/fail attestation.
4. The CRE DON calls `VerificationOracle.postVerification(taskId, passed, attestation)`. Pass → `TaskRegistry` releases reward + `AgentRegistry` bumps trust score. Fail → refund requester + penalize score.
5. Trust score / task counts live as ENSv2 text records (`com.prove.trustScore`, `com.prove.totalTasks`) on the agent's subname (`agent1.prove.eth` under `prove.eth`).

**Scope decision (2026-09-12): The Graph is deprioritized**, stretch goal only if time remains. CRE verifies directly via RPC instead of querying a subgraph — functionally equivalent for the task types in scope, and avoids subgraph indexing lag mid-demo. See `PROVE-hackathon-plan.md`'s "Scope update" note for the full reasoning. Don't reintroduce a Graph dependency into the CRE workflow's critical path without discussing it first.

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
  - **Task 1.4b done** (branch `task-1.4b-ensv2-registration-spike`, issue [#4](https://github.com/omariosman/prove-protocol/issues/4), epic [#6](https://github.com/omariosman/prove-protocol/issues/6)): `prove.eth` and `agent1.prove.eth` are **really registered on ENSv2 Sepolia** — this isn't simulated. `script/RegisterAgentENS.s.sol`, run in 3 phases (`deployInfra` / `mintApproveAndCommit` / `registerProveAndAgent`, the middle two separated by the real 60s `MIN_COMMITMENT_AGE` wait). Everything below was independently re-verified with fresh `cast call`s after broadcasting, not just trusted from the script's own log output:
    - Our own subregistry (a `UserRegistry` proxy clone via `VerifiableFactory`, deployer holds `ROLE_REGISTRAR` etc. on its `ROOT_RESOURCE`): `0x372C3F154Eb6BA69fCC1e5f54ec3229aA38c8857`
    - Our own resolver (a `PermissionedResolverImpl` proxy clone, deployer holds `ROLE_SET_TEXT`/admin on its `ROOT_RESOURCE`): `0x7add7bD84C9DB30800711a6020bA328Ef73b9A35`
    - **Why our own proxies, not the shared ENSv2 implementations**: confirmed live that the shared `PermissionedResolverImpl` already has a nonzero root-role count (someone else's admin) — EAC has no bootstrap path for an unrelated caller to gain roles on an already-initialized instance. `UserRegistry` and `PermissionedResolverImpl` are specifically designed to be cloned per-owner via `VerifiableFactory.deployProxy`, each clone's `initialize(...)` making the caller its own `ROOT_RESOURCE` admin.
    - `prove.eth` is registered, owned by the deployer wallet (`ETHRegistrar.isAvailable("prove")` now returns `false`; confirmed via `ETH_REGISTRY.getOwner`).
    - `agent1.prove.eth` is minted in our subregistry, owned by a throwaway address (`0x9E61c0fD51fD418B1dA5976D552A08269F955C94`, generated for this spike, not used for anything else).
    - Text record `com.prove.trustScore` = `"0"` on `agent1.prove.eth`, written and read back via our resolver.
    - Total cost: ~0.001 ETH gas across all 3 phases (no real funds — payment was free-minted `MockUSDC`).
    - `script/output/ens-deployment.sepolia.json` (committed) holds the subregistry/resolver addresses for reuse in #5.
    - `foundry.toml` gained `fs_permissions` for `./script/output` (needed for the script to read/write that file).
  - **Task 1.4c done** (branch `task-1.4c-agent-registry-ens-writeback`, issue [#5](https://github.com/omariosman/prove-protocol/issues/5), epic [#6](https://github.com/omariosman/prove-protocol/issues/6)): `AgentRegistry` now writes real ENSv2 text records, proven against a **Sepolia fork** (`test/AgentRegistryENSFork.t.sol`, 3 tests exercising the actual deployed resolver bytecode from #4). Notes:
    - `registerAgent` no longer uses a placeholder key — `ensNode` is now the real ENS namehash of `agent<N>.prove.eth` (`AgentRegistry.agentEnsNode(agentId)`, a `public pure` helper, self-computed via the standard recursive namehash algorithm, no external calls needed). Cross-verified against `cast namehash "agent1.prove.eth"`.
    - New `resolver` address (owner-settable via `setResolver`, default `address(0)`). If unset, `recordResult` behaves exactly as before (ENS mirroring is opt-in, not required) — this is what keeps the plain `AgentRegistry.t.sol`/`VerificationOracle.t.sol` unit tests fork-free and fast.
    - If `resolver` is set, `recordResult` also calls `IENSTextResolver(resolver).setText(...)` for both `com.prove.trustScore` (integer percent, 0-100) and `com.prove.totalTasks`, **after** updating its own storage, in the same transaction — so a revert there (e.g. missing role grant) reverts the whole call, keeping ENS and internal state consistent.
    - For this to work, `AgentRegistry` needs `ROLE_SET_TEXT` on the resolver's `ROOT_RESOURCE`, granted once by whoever holds `ROLE_SET_TEXT_ADMIN` there (the deployer, from #4's `deployInfra`). Done for real in Task 1.5 below.
    - New `src/IENSTextResolver.sol` — minimal `setText`/`text` interface, reused by `AgentRegistry` and the fork test.
  - **Task 1.5 done** (branch `task-1.5-sepolia-deploy-demo`, issue [#10](https://github.com/omariosman/prove-protocol/issues/10)): **the whole protocol is live on Sepolia, verified on Etherscan, and one complete task lifecycle has run for real** — not a test, not a fork, actual broadcast transactions with independently re-verified results. This is the reference deployment; see below for judge-facing verification steps.
    - Deployed + verified via `forge script script/Deploy.s.sol --rpc-url sepolia --broadcast --verify`:
      | Contract | Address |
      |---|---|
      | `TaskRegistry` | `0x97b2702a20375Ff7E0Db05460e512545c47BbEB1` |
      | `VerificationOracle` | `0x43669Df6dfaFcd7047b5299737E2E9C5A6d8AF7B` |
      | `AgentRegistry` | `0xbDbc1f2b9eB71af7eeCb80d37F7e7ceE404F8119` |
    - `creDON` defaults to the deployer (`CRE_DON_ADDRESS` unset) — matches the plan's documented fallback (§8), a trusted script standing in for the real CRE DON until Task 2.2.
    - Wired `AgentRegistry` to the real #4/#5 resolver (`0x7add7bD84C9DB30800711a6020bA328Ef73b9A35`): `setResolver`, then `resolver.grantRootRoles(ROLE_SET_TEXT | ROLE_SET_TEXT_ADMIN, agentRegistry)` (deployer already held admin there). Then `registerAgent(<demo agent wallet>)` → agent #1, `ensNode` = the real `agent1.prove.eth` namehash (confirmed via the `AgentRegistered` event's indexed topic).
    - Demo agent wallet (freshly generated for this run, funded with 0.003 ETH from the deployer): `0x79019E9fffFEf7188939874a512bb43e526e118D`.
    - Full real task lifecycle (task #1): requester (deployer) posted a 0.001 ETH task asking the agent to transfer 0.0002 ETH back to the requester; the agent actually performed that transfer (`0x51072cbc...`) and submitted its real tx hash as `resultHash`; the oracle then posted `passed=true` in one transaction (`0x5b801405...`) that atomically released the reward, updated `AgentRegistry`'s trust score, and wrote both ENS text records. All independently re-verified afterward with fresh `cast call`s (agent balance +0.001 ETH, task status `Paid`, `trustScore` = 1e18, resolver `text(...)` = `"100"`/`"1"`) — not just trusted from transaction logs.
    - No app-level changes in this task — deployment + wiring + a manual demo transaction sequence only (documented as exact `cast` commands, not a new script, since each step is a single simple call).
- `cre-workflow/` — TypeScript CRE workflow (Task 2.2), verifies directly via RPC, no Graph dependency — **current focus**
- `agent/` — Node.js/ethers executor script (Task 2.3)
- `frontend/` — React + wagmi + viem + ensjs (Task 3.1)
- `subgraph/` — The Graph, **deprioritized to a stretch goal** (see scope decision above) — not created yet

## ENSv2 integration notes

ENSv2 is beta, live on Sepolia, source at `ensdomains/contracts-v2` on GitHub (actively pushed to as of Sep 2026 — check for drift before relying on old notes here). **Verified 2026-09-12** by pulling deployment JSON + contract source directly via `gh api` (raw bytes, not a summarized fetch) — a prior attempt using a page-summarizing web fetch returned fabricated contract addresses. Don't trust ENSv2 addresses/interfaces from a summarized source; get them from `contracts/deployments/sepolia/*.json` or contract source in that repo, or a live on-chain read.

- Registration is priced only in stablecoins (no ETH/oracle path) — on Sepolia that's `MockUSDC`/`MockDAI`, both freely mintable via `mint(address,uint256)` (no access control). No real funds needed.
- Access control is **Enhanced Access Control (EAC)**: bitmap-packed roles scoped per-resource (`uint256 resource`, e.g. a namehash or `resource(node, part)` for a specific text-record key), not OpenZeppelin's flat `AccessControl`. Roles are granted via `grantRoles(resource, roleBitmap, account)`; `ROLE_REGISTRAR`/`ROLE_SET_TEXT`/etc. are defined in `RegistryRolesLib`/`PermissionedResolverLib`.
- To mint a subname you need a `PermissionedRegistry` you control (deployed via `VerifiableFactory`) set as the parent name's subregistry — `prove.eth` needs one deployed before subnames can be minted under it.
- **Testing against ENSv2 means forking Sepolia**, not mocking — its access-control model is too specific to fake meaningfully. Pattern (see `test/AgentRegistryENSFork.t.sol`): `vm.createSelectFork(vm.envString("SEPOLIA_RPC_URL"))` in `setUp`, then `vm.prank(<real address that holds the role on real Sepolia>)` to exercise real permission grants. Requires `SEPOLIA_RPC_URL` in `.env`.
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

- Full step-by-step registration flow is in issue [#4](https://github.com/omariosman/prove-protocol/issues/4). **Now executed for real** — see Task 1.4b above for the deployed addresses; `script/RegisterAgentENS.s.sol` is the reference implementation for every call below.
- `VerifiableFactory.deployProxy(implementation, salt, initCalldata) returns (address)` (from `ensdomains/verifiable-factory`, CREATE2-deterministic given `(msg.sender, salt)`) is how you get your own `ROOT_RESOURCE`-controlled instance of a shared implementation. Used for both the subregistry (`USER_REGISTRY_IMPL` template) and the resolver (`PERMISSIONED_RESOLVER_IMPL` template).
- `ETHRegistrar` on Sepolia: `MIN_COMMITMENT_AGE = 60s`, `MAX_COMMITMENT_AGE = 86400s`, `MIN_REGISTER_DURATION = 2419200s` (28 days) — all read live, immutable, could differ if redeployed.
- Role constants used (`RegistryRolesLib`/`PermissionedResolverLib`): `ROLE_REGISTRAR = 1<<0`, `ROLE_RENEW = 1<<16`, `ROLE_SET_RESOLVER = 1<<24`, `ROLE_SET_TEXT = 1<<4` — each role's admin variant is `role << 128`.

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

**Updated 2026-09-12.** ~~TaskRegistry + VerificationOracle~~ → ~~AgentRegistry/ENSv2~~ → **CRE workflow (direct RPC verification, current focus)** → agent script → frontend → subgraph (stretch, only if time remains). Always reserve time for the demo video — required for the Chainlink + ENS prize tracks.
