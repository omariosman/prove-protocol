import { STATUS_LABELS } from '@/lib/contracts'

const STYLES: Record<string, string> = {
	Open: 'bg-slate-700 text-slate-200',
	Executed: 'bg-amber-500/20 text-amber-300 border border-amber-500/40',
	Verified: 'bg-sky-500/20 text-sky-300 border border-sky-500/40',
	Paid: 'bg-emerald-500/20 text-emerald-300 border border-emerald-500/40',
	Failed: 'bg-rose-500/20 text-rose-300 border border-rose-500/40',
}

export function StatusBadge({ status }: { status: number }) {
	const label = STATUS_LABELS[status] ?? 'Unknown'
	return (
		<span className={`inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium ${STYLES[label] ?? STYLES.Open}`}>
			{label}
		</span>
	)
}
