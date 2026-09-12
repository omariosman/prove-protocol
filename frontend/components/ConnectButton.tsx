'use client'

import { useAccount, useConnect, useDisconnect, useSwitchChain } from 'wagmi'
import { sepolia } from 'wagmi/chains'

function short(address: string) {
	return `${address.slice(0, 6)}…${address.slice(-4)}`
}

export function ConnectButton() {
	const { address, isConnected, chainId } = useAccount()
	const { connect, connectors, isPending } = useConnect()
	const { disconnect } = useDisconnect()
	const { switchChain } = useSwitchChain()

	if (!isConnected) {
		const injected = connectors[0]
		return (
			<button
				onClick={() => injected && connect({ connector: injected })}
				disabled={!injected || isPending}
				className="rounded-lg bg-indigo-500 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-400 disabled:opacity-50"
			>
				{isPending ? 'Connecting…' : injected ? 'Connect Wallet' : 'No wallet found'}
			</button>
		)
	}

	if (chainId !== sepolia.id) {
		return (
			<button
				onClick={() => switchChain({ chainId: sepolia.id })}
				className="rounded-lg bg-rose-500 px-4 py-2 text-sm font-medium text-white hover:bg-rose-400"
			>
				Switch to Sepolia
			</button>
		)
	}

	return (
		<button
			onClick={() => disconnect()}
			className="rounded-lg border border-slate-700 px-4 py-2 text-sm font-medium text-slate-200 hover:bg-slate-800"
		>
			{short(address!)}
		</button>
	)
}
