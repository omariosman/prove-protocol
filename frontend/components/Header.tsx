import { ConnectButton } from './ConnectButton'
import { TASK_REGISTRY_ADDRESS, VERIFICATION_ORACLE_ADDRESS, AGENT_REGISTRY_ADDRESS } from '@/lib/contracts'

const CONTRACTS = [
	{ label: 'TaskRegistry', address: TASK_REGISTRY_ADDRESS },
	{ label: 'VerificationOracle', address: VERIFICATION_ORACLE_ADDRESS },
	{ label: 'AgentRegistry', address: AGENT_REGISTRY_ADDRESS },
]

export function Header() {
	return (
		<header className="border-b border-slate-800">
			<div className="mx-auto flex max-w-4xl flex-col gap-4 px-6 py-6 sm:flex-row sm:items-center sm:justify-between">
				<div>
					<div className="flex items-center gap-2">
						<h1 className="text-2xl font-bold tracking-tight">PROVE</h1>
						<span className="rounded-full bg-emerald-500/20 px-2 py-0.5 text-xs font-medium text-emerald-300 border border-emerald-500/40">
							Sepolia
						</span>
					</div>
					<p className="mt-1 text-sm text-slate-400">Verifiable AI agent execution — post a task, watch it get done, paid, and scored.</p>
				</div>
				<ConnectButton />
			</div>
			<div className="mx-auto flex max-w-4xl flex-wrap gap-x-4 gap-y-1 px-6 pb-4 text-xs text-slate-500">
				{CONTRACTS.map((c) => (
					<a
						key={c.address}
						href={`https://sepolia.etherscan.io/address/${c.address}#code`}
						target="_blank"
						rel="noreferrer"
						className="hover:text-slate-300 hover:underline"
					>
						{c.label} ↗
					</a>
				))}
			</div>
		</header>
	)
}
