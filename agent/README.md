# PROVE — Agent + Oracle Watcher

Makes the demo fully automatic: run this alongside the frontend, and pressing "Create Task" ends with the task at `Paid` live, with no manual `cast` commands.

See issue [#16](https://github.com/omariosman/prove-protocol/issues/16) and `CLAUDE.md` for context.

## What it does

One process, two polling loops (5s interval, plain HTTPS RPC — no WebSocket needed):

- **Agent loop** — watches `TaskRegistry.TaskCreated` for tasks assigned to `agent1.prove.eth`. Reads the spec, executes the real on-chain transfer it describes, calls `submitResult`.
- **Oracle loop** — watches `TaskRegistry.ResultSubmitted`. Fetches the `resultHash` transaction, runs the same comparison logic as `cre-workflow/verify-task/workflow.ts`'s `verifyTransferSpec` (recipient/amount/status match), calls `VerificationOracle.postVerification`.

This is the "Option 1" settlement path from issue #12 — `postVerification` called by a plain trusted script, not a live Chainlink CRE Forwarder integration — now automated instead of one-off manual commands.

## Run

```bash
npm install
npm start
```

Leave it running, then create a task in the frontend. Console output narrates each step:

```
[agent] New task #3 for agent1.prove.eth
[agent] Task #3: executing transfer of 0.0002 ETH to 0x...
[agent] Task #3: transfer sent 0x..., waiting for confirmation…
[agent] Task #3: submitting result…
[agent] Task #3: result submitted (proof tx 0x...)
[oracle] Task #3: result submitted, verifying…
[oracle] Task #3: verdict=PASS (transfer matches spec)
[oracle] Task #3: verification posted (0x...) — task is now Paid
```

The frontend's task feed polls every 5s too, so the status change shows up live without a page refresh.

## Requirements

- `.env` (gitignored) with `AGENT_PRIVATE_KEY` (agent1.prove.eth's wallet) and `ORACLE_PRIVATE_KEY` (the deployer/creDON key, same as `contracts/.env`'s `PRIVATE_KEY`) — see `.env.example`
- Only handles `"type": "transfer"` task specs — matches what the CRE workflow and contracts actually verify
- In-memory state only, starts watching from the current block at launch — restarting it won't re-process old tasks, and it won't backfill tasks created while it wasn't running
