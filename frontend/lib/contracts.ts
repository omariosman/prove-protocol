// Real, deployed, Etherscan-verified Sepolia contracts from Task 1.5 / #4-#5.
// See CLAUDE.md for the full deployment record.

export const TASK_REGISTRY_ADDRESS = '0x97b2702a20375Ff7E0Db05460e512545c47BbEB1' as const
export const VERIFICATION_ORACLE_ADDRESS = '0x43669Df6dfaFcd7047b5299737E2E9C5A6d8AF7B' as const
export const AGENT_REGISTRY_ADDRESS = '0xbDbc1f2b9eB71af7eeCb80d37F7e7ceE404F8119' as const
export const ENS_RESOLVER_ADDRESS = '0x7add7bD84C9DB30800711a6020bA328Ef73b9A35' as const

// The only agent registered so far (Task 1.5). agent1.prove.eth
export const AGENT1_ENS_NODE = '0xb82c859bfe39f5ecf8a57550e6f4bdd84fc3b4ed1a62edb47fbb4a477c472657' as const
export const AGENT1_ENS_NAME = 'agent1.prove.eth'
export const AGENT1_ADDRESS = '0x79019E9fffFEf7188939874a512bb43e526e118D' as const

export const SEPOLIA_RPC_URL = 'https://ethereum-sepolia-rpc.publicnode.com'

// TaskRegistry was deployed just before this block (Task 1.5) - used as a safe
// `fromBlock` floor so event log queries don't scan the whole chain.
export const TASK_REGISTRY_DEPLOY_BLOCK = BigInt(11690350)

export const STATUS_LABELS = ['Open', 'Executed', 'Verified', 'Paid', 'Failed'] as const

// TaskRegistry.reward is zeroed out once a task is Paid/Failed (the contract
// clears it as part of settlement) - so for finished tasks the original
// amount has to come from the TaskCreated event log instead of getTask().
export const taskCreatedEvent = {
	type: 'event',
	name: 'TaskCreated',
	inputs: [
		{ name: 'taskId', type: 'uint256', indexed: true },
		{ name: 'requester', type: 'address', indexed: true },
		{ name: 'agentENSNode', type: 'bytes32', indexed: true },
		{ name: 'specHash', type: 'bytes32', indexed: false },
		{ name: 'taskSpec', type: 'string', indexed: false },
		{ name: 'reward', type: 'uint256', indexed: false },
		{ name: 'deadline', type: 'uint256', indexed: false },
	],
} as const

export const taskRegistryAbi = [
	{
		type: 'function',
		name: 'taskCount',
		stateMutability: 'view',
		inputs: [],
		outputs: [{ type: 'uint256' }],
	},
	{
		type: 'function',
		name: 'getTask',
		stateMutability: 'view',
		inputs: [{ name: 'taskId', type: 'uint256' }],
		outputs: [
			{
				type: 'tuple',
				components: [
					{ name: 'requester', type: 'address' },
					{ name: 'agent', type: 'address' },
					{ name: 'agentENSNode', type: 'bytes32' },
					{ name: 'specHash', type: 'bytes32' },
					{ name: 'taskSpec', type: 'string' },
					{ name: 'reward', type: 'uint256' },
					{ name: 'deadline', type: 'uint256' },
					{ name: 'status', type: 'uint8' },
					{ name: 'resultHash', type: 'bytes32' },
				],
			},
		],
	},
	{
		type: 'function',
		name: 'createTask',
		stateMutability: 'payable',
		inputs: [
			{ name: 'agentENSNode', type: 'bytes32' },
			{ name: 'taskSpec', type: 'string' },
			{ name: 'deadline', type: 'uint256' },
		],
		outputs: [{ name: 'taskId', type: 'uint256' }],
	},
] as const

export const agentRegistryAbi = [
	{
		type: 'function',
		name: 'trustScore',
		stateMutability: 'view',
		inputs: [{ name: 'ensNode', type: 'bytes32' }],
		outputs: [{ type: 'uint256' }],
	},
	{
		type: 'function',
		name: 'getAgent',
		stateMutability: 'view',
		inputs: [{ name: 'ensNode', type: 'bytes32' }],
		outputs: [
			{
				type: 'tuple',
				components: [
					{ name: 'ensNode', type: 'bytes32' },
					{ name: 'addr', type: 'address' },
					{ name: 'ensName', type: 'string' },
					{ name: 'totalTasks', type: 'uint256' },
					{ name: 'passedTasks', type: 'uint256' },
					{ name: 'failedTasks', type: 'uint256' },
				],
			},
		],
	},
] as const

export const ensResolverAbi = [
	{
		type: 'function',
		name: 'text',
		stateMutability: 'view',
		inputs: [
			{ name: 'node', type: 'bytes32' },
			{ name: 'key', type: 'string' },
		],
		outputs: [{ type: 'string' }],
	},
] as const

export type TransferSpec = {
	type: 'transfer'
	token: string
	amount: string
	to: string
	deadline: number
}

export function parseTaskSpec(taskSpec: string): TransferSpec | null {
	try {
		const parsed = JSON.parse(taskSpec)
		if (parsed && parsed.type === 'transfer') return parsed as TransferSpec
		return null
	} catch {
		return null
	}
}
