'use client'

import { useReadContract, useReadContracts } from 'wagmi'
import {
	AGENT1_ENS_NAME,
	AGENT1_ENS_NODE,
	AGENT1_ADDRESS,
	AGENT_REGISTRY_ADDRESS,
	agentRegistryAbi,
	ENS_RESOLVER_ADDRESS,
	ensResolverAbi,
} from '@/lib/contracts'

function short(address: string) {
	return `${address.slice(0, 6)}…${address.slice(-4)}`
}

export function AgentProfile() {
	const { data: agent } = useReadContract({
		address: AGENT_REGISTRY_ADDRESS,
		abi: agentRegistryAbi,
		functionName: 'getAgent',
		args: [AGENT1_ENS_NODE],
		query: { refetchInterval: 5000 },
	})

	const { data: trustScore } = useReadContract({
		address: AGENT_REGISTRY_ADDRESS,
		abi: agentRegistryAbi,
		functionName: 'trustScore',
		args: [AGENT1_ENS_NODE],
		query: { refetchInterval: 5000 },
	})

	const { data: ensRecords } = useReadContracts({
		contracts: [
			{
				address: ENS_RESOLVER_ADDRESS,
				abi: ensResolverAbi,
				functionName: 'text',
				args: [AGENT1_ENS_NODE, 'com.prove.trustScore'],
			},
			{
				address: ENS_RESOLVER_ADDRESS,
				abi: ensResolverAbi,
				functionName: 'text',
				args: [AGENT1_ENS_NODE, 'com.prove.totalTasks'],
			},
		],
		query: { refetchInterval: 5000 },
	})

	const contractScorePct = trustScore !== undefined ? Number(trustScore) / 1e16 : null // 1e18 = 100% -> /1e16 = percent
	const ensScorePct = ensRecords?.[0]?.result
	const ensTotalTasks = ensRecords?.[1]?.result

	return (
		<section className="rounded-xl border border-slate-800 bg-slate-900/50 p-6">
			<h2 className="text-lg font-semibold">3. Agent trust score</h2>
			<p className="mt-1 text-sm text-slate-400">
				Read twice, from two independent places, and they agree — proving the on-chain reputation and the ENS record are the same source of truth.
			</p>

			<div className="mt-4 flex items-center gap-3">
				<div className="flex h-10 w-10 items-center justify-center rounded-full bg-indigo-500/20 text-sm font-bold text-indigo-300">
					{AGENT1_ENS_NAME[0].toUpperCase()}
				</div>
				<div>
					<p className="font-mono text-sm">{AGENT1_ENS_NAME}</p>
					<p className="font-mono text-xs text-slate-500">{short(AGENT1_ADDRESS)}</p>
				</div>
			</div>

			<div className="mt-5 grid gap-4 sm:grid-cols-2">
				<div className="rounded-lg border border-slate-800 bg-slate-950/60 p-4">
					<p className="text-xs uppercase tracking-wide text-slate-500">From AgentRegistry.sol</p>
					<p className="mt-1 text-3xl font-bold text-emerald-400">{contractScorePct !== null ? `${contractScorePct}%` : '—'}</p>
					<p className="mt-1 text-xs text-slate-500">
						{agent ? `${agent.passedTasks.toString()} / ${agent.totalTasks.toString()} tasks passed` : 'loading…'}
					</p>
				</div>
				<div className="rounded-lg border border-slate-800 bg-slate-950/60 p-4">
					<p className="text-xs uppercase tracking-wide text-slate-500">From live ENS text record</p>
					<p className="mt-1 text-3xl font-bold text-sky-400">{ensScorePct ? `${ensScorePct}%` : '—'}</p>
					<p className="mt-1 text-xs text-slate-500">
						com.prove.trustScore · {ensTotalTasks ?? '—'} total tasks
					</p>
				</div>
			</div>

			<a
				href={`https://sepolia.etherscan.io/address/${ENS_RESOLVER_ADDRESS}#readContract`}
				target="_blank"
				rel="noreferrer"
				className="mt-4 inline-block text-xs text-slate-500 hover:text-slate-300 hover:underline"
			>
				Read the ENS resolver yourself on Etherscan ↗
			</a>
		</section>
	)
}
