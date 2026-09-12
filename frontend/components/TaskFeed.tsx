'use client'

import { formatEther } from 'viem'
import { useReadContract, useReadContracts, usePublicClient } from 'wagmi'
import { useQuery } from '@tanstack/react-query'
import { TASK_REGISTRY_ADDRESS, TASK_REGISTRY_DEPLOY_BLOCK, taskRegistryAbi, taskCreatedEvent, parseTaskSpec } from '@/lib/contracts'
import { StatusBadge } from './StatusBadge'

function short(address: string) {
	return `${address.slice(0, 6)}…${address.slice(-4)}`
}

// TaskRegistry zeroes out `reward` once a task is Paid/Failed (settlement
// clears it), so the amount a task *originally* offered has to come from the
// TaskCreated event log rather than the current getTask() read.
function useOriginalRewards() {
	const publicClient = usePublicClient()

	return useQuery({
		queryKey: ['task-created-rewards'],
		refetchInterval: 5000,
		queryFn: async () => {
			const logs = await publicClient!.getLogs({
				address: TASK_REGISTRY_ADDRESS,
				event: taskCreatedEvent,
				fromBlock: TASK_REGISTRY_DEPLOY_BLOCK,
				toBlock: 'latest',
			})
			const rewards = new Map<number, bigint>()
			for (const log of logs) {
				if (log.args.taskId !== undefined && log.args.reward !== undefined) {
					rewards.set(Number(log.args.taskId), log.args.reward)
				}
			}
			return rewards
		},
	})
}

export function TaskFeed() {
	const { data: taskCount } = useReadContract({
		address: TASK_REGISTRY_ADDRESS,
		abi: taskRegistryAbi,
		functionName: 'taskCount',
		query: { refetchInterval: 5000 },
	})

	const count = taskCount ? Number(taskCount) : 0
	const ids = Array.from({ length: count }, (_, i) => count - i) // newest first

	const { data: tasks, isLoading } = useReadContracts({
		contracts: ids.map((id) => ({
			address: TASK_REGISTRY_ADDRESS,
			abi: taskRegistryAbi,
			functionName: 'getTask' as const,
			args: [BigInt(id)] as const,
		})),
		query: { enabled: count > 0, refetchInterval: 5000 },
	})

	const { data: originalRewards } = useOriginalRewards()

	return (
		<section className="rounded-xl border border-slate-800 bg-slate-900/50 p-6">
			<div className="flex items-baseline justify-between">
				<h2 className="text-lg font-semibold">2. Live task feed</h2>
				<span className="text-xs text-slate-500">refreshes every 5s</span>
			</div>

			{count === 0 && <p className="mt-3 text-sm text-slate-400">{isLoading ? 'Loading…' : 'No tasks yet — create one above.'}</p>}

			<ul className="mt-4 flex flex-col gap-3">
				{ids.map((id, i) => {
					const task = tasks?.[i]?.result
					if (!task) return null
					const spec = parseTaskSpec(task.taskSpec)
					const reward = originalRewards?.get(id) ?? task.reward

					return (
						<li key={id} className="rounded-lg border border-slate-800 bg-slate-950/60 p-4">
							<div className="flex flex-wrap items-center justify-between gap-2">
								<div className="flex items-center gap-2">
									<span className="font-mono text-sm text-slate-400">#{id}</span>
									<StatusBadge status={task.status} />
								</div>
								<span className="text-sm text-slate-300">{formatEther(reward)} ETH reward</span>
							</div>

							<p className="mt-2 text-sm text-slate-300">
								{spec ? (
									<>
										Transfer <span className="font-mono">{spec.amount} ETH</span> to{' '}
										<span className="font-mono">{short(spec.to)}</span>
									</>
								) : (
									<span className="font-mono text-slate-500">{task.taskSpec}</span>
								)}
							</p>

							<div className="mt-2 flex flex-wrap gap-x-4 gap-y-1 text-xs text-slate-500">
								<span>
									requester: <span className="font-mono">{short(task.requester)}</span>
								</span>
								{task.agent !== '0x0000000000000000000000000000000000000000' && (
									<span>
										agent: <span className="font-mono">{short(task.agent)}</span>
									</span>
								)}
								{task.resultHash !== '0x0000000000000000000000000000000000000000000000000000000000000000' && (
									<a
										href={`https://sepolia.etherscan.io/tx/${task.resultHash}`}
										target="_blank"
										rel="noreferrer"
										className="hover:text-slate-300 hover:underline"
									>
										proof tx ↗
									</a>
								)}
							</div>
						</li>
					)
				})}
			</ul>
		</section>
	)
}
