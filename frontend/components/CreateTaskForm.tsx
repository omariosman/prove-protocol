'use client'

import { useState } from 'react'
import { parseEther } from 'viem'
import { useAccount, useWaitForTransactionReceipt, useWriteContract } from 'wagmi'
import { AGENT1_ENS_NAME, AGENT1_ENS_NODE, TASK_REGISTRY_ADDRESS, taskRegistryAbi } from '@/lib/contracts'

export function CreateTaskForm({ onCreated }: { onCreated?: () => void }) {
	const { isConnected } = useAccount()
	const [to, setTo] = useState('')
	const [amount, setAmount] = useState('0.0002')
	const [reward, setReward] = useState('0.001')
	const [minutes, setMinutes] = useState('60')

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
			args: [AGENT1_ENS_NODE, spec, deadline],
			value: parseEther(reward),
		})
	}

	return (
		<section className="rounded-xl border border-slate-800 bg-slate-900/50 p-6">
			<h2 className="text-lg font-semibold">1. Create a task</h2>
			<p className="mt-1 text-sm text-slate-400">
				Ask <span className="font-mono text-slate-300">{AGENT1_ENS_NAME}</span> to transfer ETH to an address. It will execute on-chain, submit proof, and get verified.
			</p>

			<form onSubmit={submit} className="mt-4 grid gap-4 sm:grid-cols-2">
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
