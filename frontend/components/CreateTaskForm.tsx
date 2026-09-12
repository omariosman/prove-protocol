'use client'

import { useState } from 'react'
import { parseEther, type Hex } from 'viem'
import { useAccount, useWaitForTransactionReceipt, useWriteContract } from 'wagmi'
import { AGENTS, TASK_REGISTRY_ADDRESS, taskRegistryAbi } from '@/lib/contracts'

export function CreateTaskForm({ onCreated }: { onCreated?: () => void }) {
	const { isConnected } = useAccount()
	const [agentEnsNode, setAgentEnsNode] = useState<Hex>(AGENTS[0].ensNode)
	const [to, setTo] = useState('')
	const [amount, setAmount] = useState('0.0002')
	const [reward, setReward] = useState('0.001')
	const [minutes, setMinutes] = useState('60')

	const selectedAgent = AGENTS.find((a) => a.ensNode === agentEnsNode) ?? AGENTS[0]

	const { writeContract, data: hash, isPending, error, reset } = useWriteContract()
	const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash })

	function submit(e: React.FormEvent) {
		e.preventDefault()
		const deadline = BigInt(Math.floor(Date.now() / 1000) + Number(minutes) * 60)
		const spec = JSON.stringify({
			type: 'transfer',
			token: 'ETH',
			amount,
			to,
			deadline: Number(deadline),
		})

		writeContract({
			address: TASK_REGISTRY_ADDRESS,
			abi: taskRegistryAbi,
			functionName: 'createTask',
			args: [agentEnsNode, spec, deadline],
			value: parseEther(reward),
		})
	}

	return (
		<section className="rounded-xl border border-slate-800 bg-slate-900/50 p-6">
			<h2 className="text-lg font-semibold">1. Create a task</h2>
			<p className="mt-1 text-sm text-slate-400">Pick an AI agent by its ENS name, then describe the ETH transfer it should execute on-chain.</p>

			<form onSubmit={submit} className="mt-4 grid gap-4 sm:grid-cols-2">
				<label className="flex flex-col gap-1 text-sm sm:col-span-2">
					AI agent (by ENS name)
					<div className="flex items-center gap-3 rounded-lg border border-slate-700 bg-slate-950 px-3 py-2">
						<span className="flex h-7 w-7 shrink-0 items-center justify-center rounded-full bg-indigo-500/20 text-xs font-bold text-indigo-300">
							{selectedAgent.ensName[0].toUpperCase()}
						</span>
						<select
							value={agentEnsNode}
							onChange={(e) => setAgentEnsNode(e.target.value as Hex)}
							className="w-full bg-transparent font-mono text-sm text-slate-100 outline-none"
						>
							{AGENTS.map((a) => (
								<option key={a.ensNode} value={a.ensNode} className="bg-slate-950">
									{a.ensName}
								</option>
							))}
						</select>
						<span className="shrink-0 rounded-full bg-sky-500/20 px-2 py-0.5 text-[10px] font-medium uppercase tracking-wide text-sky-300 border border-sky-500/40">
							ENS
						</span>
					</div>
				</label>

				<label className="flex flex-col gap-1 text-sm sm:col-span-2">
					Recipient address
					<input
						required
						value={to}
						onChange={(e) => setTo(e.target.value)}
						placeholder="0x..."
						className="rounded-lg border border-slate-700 bg-slate-950 px-3 py-2 font-mono text-sm outline-none focus:border-indigo-500"
					/>
				</label>

				<label className="flex flex-col gap-1 text-sm">
					Amount to transfer (ETH)
					<input
						required
						value={amount}
						onChange={(e) => setAmount(e.target.value)}
						className="rounded-lg border border-slate-700 bg-slate-950 px-3 py-2 text-sm outline-none focus:border-indigo-500"
					/>
				</label>

				<label className="flex flex-col gap-1 text-sm">
					Reward (ETH)
					<input
						required
						value={reward}
						onChange={(e) => setReward(e.target.value)}
						className="rounded-lg border border-slate-700 bg-slate-950 px-3 py-2 text-sm outline-none focus:border-indigo-500"
					/>
				</label>

				<label className="flex flex-col gap-1 text-sm">
					Deadline (minutes from now)
					<input
						required
						value={minutes}
						onChange={(e) => setMinutes(e.target.value)}
						className="rounded-lg border border-slate-700 bg-slate-950 px-3 py-2 text-sm outline-none focus:border-indigo-500"
					/>
				</label>

				<div className="flex items-end sm:col-span-1">
					<button
						type="submit"
						disabled={!isConnected || isPending || isConfirming}
						className="w-full rounded-lg bg-indigo-500 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-400 disabled:opacity-50"
					>
						{!isConnected ? 'Connect wallet first' : isPending ? 'Confirm in wallet…' : isConfirming ? 'Creating…' : 'Create Task'}
					</button>
				</div>
			</form>

			{hash && (
				<p className="mt-3 text-xs text-slate-400">
					Tx:{' '}
					<a href={`https://sepolia.etherscan.io/tx/${hash}`} target="_blank" rel="noreferrer" className="font-mono text-indigo-400 hover:underline">
						{hash}
					</a>
				</p>
			)}
			{isSuccess && (
				<p className="mt-2 text-sm text-emerald-400">
					Task created! Watch it appear below.{' '}
					<button type="button" onClick={() => { reset(); onCreated?.() }} className="underline">
						Create another
					</button>
				</p>
			)}
			{error && <p className="mt-2 text-sm text-rose-400">{error.message.split('\n')[0]}</p>}
		</section>
	)
}
