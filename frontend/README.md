# PROVE — Frontend

One-page Next.js 14 dashboard demonstrating PROVE's task lifecycle end to end: create a task, watch it get executed/verified/paid live, and see the agent's trust score agree between `AgentRegistry` and its live ENS text record. Reads the real deployed Sepolia contracts from Task 1.5 — no mocks, no backend, no database.

See issue [#14](https://github.com/omariosman/prove-protocol/issues/14) for the design plan and `CLAUDE.md` for the full project context.

## Stack

- Next.js 14 (App Router, TypeScript), pinned per request for stability
- Tailwind CSS
- wagmi v2 + viem — wallet connection (injected connector only, no WalletConnect/RainbowKit) and all contract reads/writes
- No backend — every read/write goes straight to Sepolia from the browser

## Run locally

```bash
npm install
npm run dev
```

Open http://localhost:3000. Read-only sections (task feed, agent profile) work without connecting a wallet; creating a task needs a connected wallet on Sepolia.

## Structure

```
app/
  layout.tsx      # wraps the app in Providers (wagmi + react-query)
  page.tsx         # the single dashboard page
  providers.tsx
components/
  Header.tsx        # title, network badge, connect button, contract links
  CreateTaskForm.tsx # calls TaskRegistry.createTask
  TaskFeed.tsx       # all tasks, polls every 5s, live status badges
  AgentProfile.tsx   # trust score from AgentRegistry + the ENS resolver, side by side
  StatusBadge.tsx
  ConnectButton.tsx
  Footer.tsx
lib/
  contracts.ts     # deployed addresses + minimal ABIs
  wagmi.ts          # wagmi config (Sepolia only)
```

## Notes

- `TaskRegistry.reward` is zeroed by the contract once a task is `Paid`/`Failed` (settlement clears it) — the feed reads the original amount from the `TaskCreated` event log instead of `getTask()` for finished tasks.
- Next.js 14.2.35 is the latest stable 14.x release; some npm-audit-flagged CVEs in that line are fixed only in 15+. Acceptable for a short-lived hackathon demo per the explicit request to pin to v14 for stability.
