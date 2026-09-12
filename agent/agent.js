// PROVE agent + oracle watcher.
//
// Two polling loops, one process:
//   - agent loop:  watches TaskRegistry.TaskCreated for agent1.prove.eth,
//                  executes the described transfer, calls submitResult.
//   - oracle loop: watches TaskRegistry.ResultSubmitted, verifies the result
//                  (same comparison logic as cre-workflow/verify-task/workflow.ts's
//                  verifyTransferSpec), calls VerificationOracle.postVerification.
//

import 'dotenv/config'
import { createPublicClient, createWalletClient, http, parseEther, keccak256, stringToHex } from 'viem'
import { privateKeyToAccount } from 'viem/accounts'
import { sepolia } from 'viem/chains'

// ---- Config ----
const RPC_URL = process.env.SEPOLIA_RPC_URL || 'https://ethereum-sepolia-rpc.publicnode.com'
const AGENT_PRIVATE_KEY = process.env.AGENT_PRIVATE_KEY
const ORACLE_PRIVATE_KEY = process.env.ORACLE_PRIVATE_KEY
const POLL_INTERVAL_MS = Number(process.env.POLL_INTERVAL_MS || 5000)

if (!AGENT_PRIVATE_KEY || !ORACLE_PRIVATE_KEY) {
	console.error('Missing AGENT_PRIVATE_KEY or ORACLE_PRIVATE_KEY - copy .env.example to .env and fill them in.')
	process.exit(1)
}

// Real, deployed, Etherscan-verified Sepolia contracts
const TASK_REGISTRY_ADDRESS = '0x97b2702a20375Ff7E0Db05460e512545c47BbEB1'
const VERIFICATION_ORACLE_ADDRESS = '0x43669Df6dfaFcd7047b5299737E2E9C5A6d8AF7B'
const AGENT1_ENS_NODE = '0xb82c859bfe39f5ecf8a57550e6f4bdd84fc3b4ed1a62edb47fbb4a477c472657'

const taskRegistryAbi = [
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
		name: 'submitResult',
		stateMutability: 'nonpayable',
		inputs: [
			{ name: 'taskId', type: 'uint256' },
			{ name: 'resultHash', type: 'bytes32' },
		],
		outputs: [],
	},
	{
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
	},
	{
		type: 'event',
		name: 'ResultSubmitted',
		inputs: [
			{ name: 'taskId', type: 'uint256', indexed: true },
			{ name: 'agent', type: 'address', indexed: true },
			{ name: 'resultHash', type: 'bytes32', indexed: false },
		],
	},
]

const verificationOracleAbi = [
	{
		type: 'function',
		name: 'postVerification',
		stateMutability: 'nonpayable',
		inputs: [
			{ name: 'taskId', type: 'uint256' },
			{ name: 'passed', type: 'bool' },
			{ name: 'attestation', type: 'bytes' },
		],
		outputs: [],
	},
]

// ---- Clients ----
const agentAccount = privateKeyToAccount(AGENT_PRIVATE_KEY)
const oracleAccount = privateKeyToAccount(ORACLE_PRIVATE_KEY)

const publicClient = createPublicClient({ chain: sepolia, transport: http(RPC_URL) })
const agentWallet = createWalletClient({ account: agentAccount, chain: sepolia, transport: http(RPC_URL) })
const oracleWallet = createWalletClient({ account: oracleAccount, chain: sepolia, transport: http(RPC_URL) })

// ---- Verification logic ----
// Mirrors cre-workflow/verify-task/workflow.ts's verifyTransferSpec exactly,
// so the automated settlement path and the CRE Confidential Workflow agree
// on what "passing" means.
function verifyTransferSpec(spec, tx, receiptStatus) {
	if (receiptStatus !== 'success') return { passed: false, reason: 'transaction reverted' }
	if (!tx.to || tx.to.toLowerCase() !== spec.to.toLowerCase()) {
		return { passed: false, reason: 'recipient does not match spec' }
	}
	const expectedWei = parseEther(spec.amount)
	if (tx.value !== expectedWei) return { passed: false, reason: 'amount does not match spec' }
	return { passed: true, reason: 'transfer matches spec' }
}

function parseTaskSpec(taskSpecJson) {
	try {
		const spec = JSON.parse(taskSpecJson)
		if (spec && spec.type === 'transfer') return spec
	} catch {
		// fall through
	}
	return null
}

// ---- State (in-memory only - this is a demo script, not a production indexer) ----
const processedCreated = new Set()
const processedResults = new Set()
let lastCreatedBlock
let lastResultBlock

async function handleNewTask(taskId) {
	if (processedCreated.has(taskId)) return
	processedCreated.add(taskId)

	console.log(`[agent] New task #${taskId} for agent1.prove.eth`)
	const task = await publicClient.readContract({
		address: TASK_REGISTRY_ADDRESS,
		abi: taskRegistryAbi,
		functionName: 'getTask',
		args: [taskId],
	})

	const spec = parseTaskSpec(task.taskSpec)
	if (!spec) {
		console.log(`[agent] Task #${taskId}: unsupported spec, skipping — ${task.taskSpec}`)
		return
	}

	console.log(`[agent] Task #${taskId}: executing transfer of ${spec.amount} ETH to ${spec.to}`)
	const txHash = await agentWallet.sendTransaction({ to: spec.to, value: parseEther(spec.amount) })
	console.log(`[agent] Task #${taskId}: transfer sent ${txHash}, waiting for confirmation…`)
	await publicClient.waitForTransactionReceipt({ hash: txHash })

	console.log(`[agent] Task #${taskId}: submitting result…`)
	const submitTxHash = await agentWallet.writeContract({
		address: TASK_REGISTRY_ADDRESS,
		abi: taskRegistryAbi,
		functionName: 'submitResult',
		args: [taskId, txHash],
	})
	await publicClient.waitForTransactionReceipt({ hash: submitTxHash })
	console.log(`[agent] Task #${taskId}: result submitted (proof tx ${txHash})`)
}

async function handleResultSubmitted(taskId) {
	if (processedResults.has(taskId)) return
	processedResults.add(taskId)

	console.log(`[oracle] Task #${taskId}: result submitted, verifying…`)
	const task = await publicClient.readContract({
		address: TASK_REGISTRY_ADDRESS,
		abi: taskRegistryAbi,
		functionName: 'getTask',
		args: [taskId],
	})

	if (task.status !== 1) {
		console.log(`[oracle] Task #${taskId}: not in Executed state (status=${task.status}), skipping`)
		return
	}

	const spec = parseTaskSpec(task.taskSpec)
	const [tx, receipt] = await Promise.all([
		publicClient.getTransaction({ hash: task.resultHash }),
		publicClient.getTransactionReceipt({ hash: task.resultHash }),
	])

	const { passed, reason } = spec
		? verifyTransferSpec(spec, tx, receipt.status)
		: { passed: false, reason: 'unsupported task type' }

	console.log(`[oracle] Task #${taskId}: verdict=${passed ? 'PASS' : 'FAIL'} (${reason})`)

	const attestation = keccak256(stringToHex(`prove-agent-task-${taskId}-${passed}-${reason}`))
	const verifyTxHash = await oracleWallet.writeContract({
		address: VERIFICATION_ORACLE_ADDRESS,
		abi: verificationOracleAbi,
		functionName: 'postVerification',
		args: [taskId, passed, attestation],
	})
	await publicClient.waitForTransactionReceipt({ hash: verifyTxHash })
	console.log(`[oracle] Task #${taskId}: verification posted (${verifyTxHash}) — task is now ${passed ? 'Paid' : 'Failed'}`)
}

async function pollTaskCreated() {
	const toBlock = await publicClient.getBlockNumber()
	if (toBlock < lastCreatedBlock) return
	const logs = await publicClient.getContractEvents({
		address: TASK_REGISTRY_ADDRESS,
		abi: taskRegistryAbi,
		eventName: 'TaskCreated',
		fromBlock: lastCreatedBlock,
		toBlock,
	})
	lastCreatedBlock = toBlock + 1n

	for (const log of logs) {
		if (log.args.agentENSNode?.toLowerCase() !== AGENT1_ENS_NODE.toLowerCase()) continue
		await handleNewTask(log.args.taskId).catch((err) =>
			console.error(`[agent] Task #${log.args.taskId} failed:`, err.shortMessage || err.message),
		)
	}
}

async function pollResultSubmitted() {
	const toBlock = await publicClient.getBlockNumber()
	if (toBlock < lastResultBlock) return
	const logs = await publicClient.getContractEvents({
		address: TASK_REGISTRY_ADDRESS,
		abi: taskRegistryAbi,
		eventName: 'ResultSubmitted',
		fromBlock: lastResultBlock,
		toBlock,
	})
	lastResultBlock = toBlock + 1n

	for (const log of logs) {
		await handleResultSubmitted(log.args.taskId).catch((err) =>
			console.error(`[oracle] Task #${log.args.taskId} failed:`, err.shortMessage || err.message),
		)
	}
}

async function main() {
	console.log('PROVE agent + oracle watcher starting…')
	console.log(`  agent wallet:  ${agentAccount.address}`)
	console.log(`  oracle wallet: ${oracleAccount.address}`)

	const startBlock = await publicClient.getBlockNumber()
	lastCreatedBlock = startBlock
	lastResultBlock = startBlock
	console.log(`Watching from block ${startBlock}. Create a task in the frontend — it will execute and settle automatically.\n`)

	setInterval(() => {
		pollTaskCreated().catch((err) => console.error('[agent] poll error:', err.message))
		pollResultSubmitted().catch((err) => console.error('[oracle] poll error:', err.message))
	}, POLL_INTERVAL_MS)
}

main()
