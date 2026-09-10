# PROVE — Protocol for Reputation and On-chain Verified Execution

## Hackathon Implementation Plan

**Event:** ETH Online 2026
**Target Prizes:** The Graph ($5k) + Chainlink ($2k) + ENS ($4.5k) = $11,500 potential
**Network:** Ethereum Sepolia (required by ENSv2)

---

## 1. The Idea in One Paragraph

PROVE is a protocol that verifies AI agents did what they were asked to do. A task requester posts a job on-chain with a spec and a reward. An AI agent picks it up, executes on-chain actions, and submits a result. A Chainlink CRE Confidential Workflow (running in a TEE) then queries The Graph for what actually happened on-chain, compares it against the original task spec, and posts a pass/fail attestation. If the agent passes, the reward is released. The agent's trust score is recorded on its ENSv2 identity — building verifiable reputation for AI agents.

---

## 2. System Components

### Smart Contracts (Solidity + Foundry)

#### A. TaskRegistry.sol
- `createTask(bytes32 agentENSNode, string taskSpec, uint256 reward)` — requester deposits ETH/ERC20 as reward
- `submitResult(uint256 taskId, bytes resultHash)` — agent submits execution proof
- Emits `TaskCreated`, `ResultSubmitted` events (for The Graph to index)
- Stores: taskId, spec hash, agent address, deadline, reward amount, status enum (Open → Executed → Verified → Paid / Failed)

#### B. VerificationOracle.sol
- `postVerification(uint256 taskId, bool passed, bytes attestation)` — called by Chainlink CRE
- If passed → releases reward to agent, updates agent's ENS trust score
- If failed → returns reward to requester, penalizes agent score
- Access controlled: only the CRE DON can call this

#### C. AgentRegistry.sol (ENSv2 Integration)
- Manages subnames under a parent ENS name (e.g. `prove.eth`)
- `registerAgent(string label, address agentAddress)` → creates `agent1.prove.eth`
- Stores trust score, total tasks, pass rate as ENS text records
- Uses Enhanced Access Control to delegate:
  - `TASK_ASSIGNER` role → who can assign tasks to this agent
  - `SCORE_UPDATER` role → only VerificationOracle can update scores

### The Graph Subgraph

Indexes events from TaskRegistry and VerificationOracle:

```graphql
type Task @entity {
  id: ID!                    # taskId
  requester: Bytes!
  agent: Bytes!
  agentENSNode: Bytes!
  taskSpec: String!
  reward: BigInt!
  status: String!            # Open, Executed, Verified, Failed
  resultHash: Bytes
  verified: Boolean
  createdAt: BigInt!
  executedAt: BigInt
  verifiedAt: BigInt
}

type Agent @entity {
  id: ID!                    # agent address
  ensNode: Bytes!
  totalTasks: Int!
  passedTasks: Int!
  failedTasks: Int!
  trustScore: BigDecimal!    # passedTasks / totalTasks
  tasks: [Task!]!
}

type VerificationEvent @entity {
  id: ID!
  taskId: BigInt!
  passed: Boolean!
  attestation: Bytes!
  timestamp: BigInt!
}
```

### Chainlink CRE Confidential Workflow

The verification engine — runs in a TEE:

```
Trigger: TaskRegistry.ResultSubmitted event
→ Inside TEE:
  1. Fetch task spec from TaskRegistry (on-chain read)
  2. Query The Graph Subgraph for agent's actual on-chain actions
  3. Parse the task spec (e.g., "swap 100 USDC for ETH on Uniswap")
  4. Compare spec vs actual execution data from Subgraph
  5. Run verification logic:
     - Did the right function get called?
     - Were the parameters correct?
     - Was it completed before the deadline?
     - Did the output match expected criteria?
  6. Produce attestation (pass/fail + evidence hash)
→ Post attestation to VerificationOracle.sol
```

### Frontend (Simple React App)

- Connect wallet
- Create a task (fill spec, set reward, pick agent by ENS name)
- View agent profiles (resolve ENSv2 subnames, show trust scores)
- View task status and verification results
- Dashboard showing all tasks and their verification status

---

## 3. Implementation Tasks (Day by Day)

### Day 1: Foundation (Smart Contracts + Setup)

**Task 1.1 — Project Setup (1 hour)**
```bash
forge init prove && cd prove
forge install OpenZeppelin/openzeppelin-contracts
forge install smartcontractkit/chainlink  # for CRE interfaces
```
- Set up Foundry project structure
- Configure Sepolia RPC and deployment scripts
- Set up `.env` with private keys, Sepolia RPC, Etherscan API key

**Task 1.2 — TaskRegistry.sol (3 hours)**
- Write the contract with:
  - Task struct (id, requester, agent, specHash, reward, status, deadline)
  - `createTask()` — accepts ETH, stores task, emits event
  - `submitResult()` — agent marks task as executed, emits event
  - `releaseReward()` — internal, called after verification passes
  - `refundReward()` — internal, called after verification fails
- Write Foundry tests for all flows
- Deploy to Sepolia

**Task 1.3 — VerificationOracle.sol (2 hours)**
- Write the contract:
  - `postVerification(taskId, passed, attestation)` — restricted to CRE DON address
  - Calls TaskRegistry to release/refund reward
  - Calls AgentRegistry to update trust score
  - Emits `VerificationPosted` event
- Write tests
- Deploy to Sepolia

**Task 1.4 — AgentRegistry.sol + ENSv2 (3 hours)**
- Integrate with ENSv2 on Sepolia:
  - Register parent name `prove.eth` using ENSv2 Permissioned Registry
  - Implement `registerAgent()` using ENSv2 subname creation
  - Set up Permissioned Resolver for agent subnames
  - Configure Enhanced Access Control:
    - `TASK_ASSIGNER` role on each agent subname
    - `SCORE_UPDATER` role → only VerificationOracle address
  - Store trust score as a custom text record: `com.prove.trustScore`
  - Store task count as: `com.prove.totalTasks`
- Write tests
- Deploy to Sepolia

**Day 1 Deliverable:** All 3 contracts deployed on Sepolia, verified on Etherscan

---

### Day 2: Data Layer + Verification Engine

**Task 2.1 — The Graph Subgraph (3 hours)**
- Initialize subgraph:
  ```bash
  graph init --studio prove-subgraph
  ```
- Write `subgraph.yaml` pointing to deployed contracts on Sepolia
- Write `schema.graphql` (Task, Agent, VerificationEvent entities)
- Write event handlers in `src/mapping.ts`:
  - `handleTaskCreated` → create Task entity
  - `handleResultSubmitted` → update Task status, link to Agent
  - `handleVerificationPosted` → update Task, update Agent trust score
- Deploy to Subgraph Studio
- Test with GraphQL queries:
  ```graphql
  {
    tasks(where: { status: "Executed" }) {
      id
      taskSpec
      agent { trustScore }
    }
  }
  ```

**Task 2.2 — Chainlink CRE Confidential Workflow (4 hours)**
- Set up CRE development environment
- Write the workflow in TypeScript:
  ```typescript
  // Confidential handler — runs inside TEE
  const verifyExecution = handlerInTee(async (input) => {
    // 1. Read task spec from input (passed from trigger)
    const taskSpec = input.taskSpec;
    const taskId = input.taskId;
    
    // 2. Query The Graph for agent's actual actions
    const subgraphData = await fetch(SUBGRAPH_URL, {
      method: 'POST',
      body: JSON.stringify({
        query: `{ task(id: "${taskId}") { 
          agent { id } resultHash status 
        }}`
      })
    });
    
    // 3. Verification logic (confidential)
    const passed = verifyTaskCompletion(taskSpec, subgraphData);
    
    // 4. Return attestation
    return { taskId, passed, attestation: hash(evidence) };
  });
  ```
- Write verification logic:
  - Parse task spec (simple JSON format for PoC)
  - Compare expected vs actual from Subgraph data
  - Generate attestation hash
- Test with CRE CLI simulation
- Deploy workflow

**Task 2.3 — Simulated AI Agent Script (2 hours)**
- Write a simple Node.js/Python script that acts as the AI agent:
  - Listens for `TaskCreated` events
  - Parses the task spec
  - Executes the required on-chain action (e.g., a token transfer, a swap)
  - Calls `submitResult()` on TaskRegistry
- This doesn't need to be a real AI agent — it's a PoC
  - For the demo: hardcode 2-3 task types the agent can handle
  - Example tasks:
    1. "Transfer 0.01 ETH to address X" → agent does the transfer
    2. "Approve token X for spender Y" → agent does the approval
    3. "Call function Z on contract W" → agent calls it

**Day 2 Deliverable:** Subgraph deployed and indexing, CRE workflow simulated, agent script working

---

### Day 3: Frontend + Integration + Demo

**Task 3.1 — Frontend Dashboard (4 hours)**
- React app with wagmi/viem for wallet connection
- Pages:
  1. **Create Task** — form to specify task, set reward, pick agent ENS name
  2. **Agent Directory** — list agents by ENS subnames, show trust scores
  3. **Task Feed** — live view of tasks with status (Open → Executed → Verified)
  4. **Agent Profile** — resolve ENSv2 name, show verification history from Subgraph
- Query The Graph Subgraph for all data display
- Resolve ENSv2 names using ensjs library

**Task 3.2 — End-to-End Integration Test (2 hours)**
- Run the full flow on Sepolia:
  1. Register an agent → gets `agent1.prove.eth`
  2. Create a task with reward
  3. Agent picks up and executes the task
  4. CRE workflow verifies execution
  5. Reward released, trust score updated
  6. Query agent's ENS name → see updated trust score
- Fix any integration bugs
- Record terminal logs for the demo

**Task 3.3 — Demo Video (2 hours)**
- Record 3-4 minute demo covering:
  1. Problem statement (30 sec): "AI agents act on-chain but nobody verifies they did it right"
  2. Architecture walkthrough (30 sec): show the diagram
  3. Live demo (2 min):
     - Register agent on ENSv2
     - Create a task
     - Watch agent execute it
     - Watch CRE verify it
     - Show trust score update on ENS
  4. Tech stack summary (30 sec): The Graph + Chainlink CRE + ENSv2
- Upload to YouTube/Loom

**Task 3.4 — Submission Package (1 hour)**
- Clean up GitHub repo with comprehensive README:
  - Architecture diagram
  - Setup instructions
  - Contract addresses on Sepolia
  - Subgraph URL
  - Demo video link
- Write FEEDBACK.md (for Uniswap if you add their integration as bonus)
- Submit on ETHGlobal:
  - Tag all 3 prize tracks
  - Include demo video
  - Link GitHub repo

---

## 4. Task Spec Format (for PoC)

Keep it simple — JSON-based task specs:

```json
{
  "type": "transfer",
  "token": "ETH",
  "amount": "0.01",
  "to": "0x1234...abcd",
  "deadline": 1726000000
}
```

```json
{
  "type": "approve",
  "token": "0xUSDC...",
  "spender": "0xRouter...",
  "amount": "1000000000"
}
```

The CRE workflow parses this and checks The Graph data to confirm the agent actually performed the specified action.

---

## 5. What Makes This Win Each Prize

### The Graph ($5,000) — "Best AI Tooling"
✅ The Graph is the source of truth for verification — not cosmetic
✅ Subgraph indexes all agent actions and verification events
✅ CRE workflow queries the Subgraph as its primary data source
✅ AI agent tooling use case — infrastructure for the agentic economy
✅ Live data from Subgraph Studio (not mocked)
✅ "Start Fresh" pool — all new code

### Chainlink ($2,000) — "Best Confidential Workflow"
✅ CRE Confidential Workflow is THE verification engine
✅ Sensitive verification logic runs in TEE (task specs, evaluation criteria)
✅ Processes confidential inputs (agent strategies, scoring rubrics)
✅ Produces public attestation from confidential computation
✅ Meaningful integration — not a placeholder

### ENS ($4,500) — "Best Use of ENSv2"
✅ Built on ENSv2 Sepolia — required
✅ Hierarchical registry: `prove.eth` → `agent1.prove.eth`, `agent2.prove.eth`
✅ Enhanced Access Control: TASK_ASSIGNER and SCORE_UPDATER roles
✅ Permissioned Resolver: stores trust scores, task history
✅ Central to product — agents ARE their ENS names
✅ AI agent identity use case — bonus points per prize description

---

## 6. Tech Stack Summary

| Layer | Technology |
|-------|-----------|
| Smart Contracts | Solidity + Foundry |
| Network | Ethereum Sepolia |
| Data Indexing | The Graph (Subgraph Studio) |
| Verification | Chainlink CRE Confidential Workflows |
| Agent Identity | ENSv2 (Permissioned Registry + Resolver + EAC) |
| Frontend | React + wagmi + viem + ensjs |
| Agent Script | Node.js (ethers.js) |
| Demo | Loom/YouTube |

---

## 7. Repo Structure

```
prove/
├── contracts/
│   ├── src/
│   │   ├── TaskRegistry.sol
│   │   ├── VerificationOracle.sol
│   │   └── AgentRegistry.sol
│   ├── test/
│   │   ├── TaskRegistry.t.sol
│   │   ├── VerificationOracle.t.sol
│   │   └── AgentRegistry.t.sol
│   ├── script/
│   │   └── Deploy.s.sol
│   └── foundry.toml
├── subgraph/
│   ├── schema.graphql
│   ├── subgraph.yaml
│   └── src/
│       └── mapping.ts
├── cre-workflow/
│   ├── workflow.ts
│   └── verification-logic.ts
├── agent/
│   └── agent.ts
├── frontend/
│   ├── src/
│   │   ├── App.tsx
│   │   ├── pages/
│   │   │   ├── CreateTask.tsx
│   │   │   ├── AgentDirectory.tsx
│   │   │   ├── TaskFeed.tsx
│   │   │   └── AgentProfile.tsx
│   │   └── hooks/
│   │       ├── useSubgraph.ts
│   │       └── useENS.ts
│   └── package.json
├── README.md
└── FEEDBACK.md
```

---

## 8. Risk Mitigation

| Risk | Mitigation |
|------|-----------|
| CRE simulation fails | Fall back to a simulated oracle — a script that runs the same logic off-chain and posts to VerificationOracle. Judges care about the design, not perfect CRE deployment |
| ENSv2 beta has bugs | Have a fallback ENS mock contract that mirrors the same interface. Document the intended ENSv2 integration clearly |
| Subgraph indexing is slow | Pre-create test data on Sepolia before demo. Have cached query results ready |
| Running out of time | Priority order: Contracts → Subgraph → CRE → Frontend. A working contract + subgraph + CLI demo can still win without a pretty UI |

---

## 9. Priority Order (If Short on Time)

If you can't finish everything, build in this order:

1. **TaskRegistry.sol + VerificationOracle.sol** — the core protocol
2. **The Graph Subgraph** — indexes everything, proves The Graph integration
3. **AgentRegistry.sol with ENSv2** — agent identity layer
4. **CRE Workflow** (even just a simulation) — verification engine
5. **Agent script** — simple executor for demo
6. **Frontend** — nice to have but not required to win
7. **Demo video** — REQUIRED, always save 2 hours for this

The demo video is non-negotiable for all 3 prizes. A clean 3-minute video showing the flow working beats a polished UI with no explanation.
