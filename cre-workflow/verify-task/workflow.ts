import {
	cre,
	bytesToHex,
	bytesToBase64,
	hexToBase64,
	ok,
	json,
	getNetwork,
	encodeCallMsg,
	logTriggerConfig,
	LAST_FINALIZED_BLOCK_NUMBER,
	type EVMLog,
	type TeeRuntime,
} from '@chainlink/cre-sdk'
import {
	parseAbi,
	decodeFunctionResult,
	encodeFunctionData,
	encodeAbiParameters,
	parseAbiParameters,
	parseEther,
	zeroAddress,
	type Address,
	type Hex,
} from 'viem'
import { z } from 'zod'

// ─── Config Schema ──────────────────────────────────────────
export const configSchema = z.object({
	taskRegistryAddress: z.string(),
	chainSelectorName: z.string(),
	rpcUrl: z.string(),
})
type Config = z.infer<typeof configSchema>

const TASK_REGISTRY_ABI = parseAbi([
	'function getTask(uint256 taskId) external view returns ((address requester, address agent, bytes32 agentENSNode, bytes32 specHash, string taskSpec, uint256 reward, uint256 deadline, uint8 status, bytes32 resultHash))',
])

// keccak256("ResultSubmitted(uint256,address,bytes32)") - see CLAUDE.md.
const RESULT_SUBMITTED_TOPIC0: Hex = '0x9bb2295443670abcb0f3088e52668e961eca6816b19f155f2fca528c4b2fe345'

type TransferSpec = {
	type: 'transfer'
	token: string
	amount: string
	to: string
	deadline: number
}

// ─── Logic to be executed over confidential data ────────────
// This is PROVE's core verification step: comparing what a requester asked for
// against what the agent actually did on-chain. The comparison itself - a
// requester's exact verification criteria, evaluated against the agent's raw
// transaction data - is treated as sensitive here: revealing the precise
// rubric or the raw execution data to node operators before a verdict is
// final could let them front-run or game verification. Only the pass/fail
// verdict crosses back out to the DON.
//
// Keep it deterministic for a given input - the enclave result is attested
// and verified by DON consensus before the workflow completes.
export const verifyTransferSpec = (
	spec: TransferSpec,
	tx: { to: string | null; value: string },
	receiptStatus: string,
): { passed: boolean; reason: string } => {
	if (receiptStatus !== '0x1') {
		return { passed: false, reason: 'transaction reverted' }
	}
	if (!tx.to || tx.to.toLowerCase() !== spec.to.toLowerCase()) {
		return { passed: false, reason: 'recipient does not match spec' }
	}
	const expectedWei = parseEther(spec.amount)
	const actualWei = BigInt(tx.value)
	if (actualWei !== expectedWei) {
		return { passed: false, reason: 'amount does not match spec' }
	}
	return { passed: true, reason: 'transfer matches spec' }
}

// ─── Confidential JSON-RPC ───────────────────────────────────
// evmClient's own chain-read methods only accept a plain Runtime - chain
// reads always execute on Workflow DON nodes, never inside the enclave (see
// CLAUDE.md "ENSv2/CRE integration notes" and the confidential-workflows
// skill reference). To keep the agent's raw transaction data confidential
// until a verdict is reached, fetch it via a plain JSON-RPC POST through
// HTTPClient's TeeRuntime overload, which does execute from inside the
// enclave - request and response payloads stay confidential from node
// operators.
const rpcCall = <T>(runtime: TeeRuntime<Config>, method: string, params: unknown[]): T => {
	const payload = JSON.stringify({ jsonrpc: '2.0', id: 1, method, params })

	const response = new cre.capabilities.HTTPClient()
		.sendRequest(runtime, {
			url: runtime.config.rpcUrl,
			method: 'POST',
			multiHeaders: {
				'Content-Type': { values: ['application/json'] },
			},
			body: bytesToBase64(new TextEncoder().encode(payload)),
			cacheSettings: { store: false },
		})
		.result()

	if (!ok(response)) {
		throw new Error(`RPC call ${method} failed with status: ${response.statusCode}`)
	}

	const body = json(response) as { result?: T; error?: { message: string } }
	if (body.error) {
		throw new Error(`RPC call ${method} failed: ${body.error.message}`)
	}
	if (body.result === undefined || body.result === null) {
		throw new Error(`RPC call ${method} returned no result`)
	}
	return body.result
}

// ─── TEE EVM Log Callback ─────────────────────────────────────
// Receives a TeeRuntime, not a Runtime. Everything here runs inside the
// enclave until explicitly crossed back with usingTheDons().
export const onResultSubmitted = (runtime: TeeRuntime<Config>, log: EVMLog): string => {
	const config = runtime.config

	// topics[0] is the event signature; topics[1] is the first indexed param
	// (taskId) of `ResultSubmitted(uint256 indexed taskId, address indexed
	// agent, bytes32 resultHash)`.
	const taskId = BigInt(bytesToHex(log.topics[1]))

	// ── Public on-chain read: cross to the DON runtime. Chain reads always
	// run on Workflow DON nodes and are never confidential - which is fine
	// here, the task spec is already public contract state.
	const network = getNetwork({ chainFamily: 'evm', chainSelectorName: config.chainSelectorName })
	if (!network) {
		throw new Error(`Unknown chain selector name: ${config.chainSelectorName}`)
	}
	const donRuntime = runtime.usingTheDons()
	const evmClient = new cre.capabilities.EVMClient(network.chainSelector.selector)

	const callData = encodeFunctionData({
		abi: TASK_REGISTRY_ABI,
		functionName: 'getTask',
		args: [taskId],
	})
	const callResult = evmClient
		.callContract(donRuntime, {
			call: encodeCallMsg({
				from: zeroAddress,
				to: config.taskRegistryAddress as Address,
				data: callData,
			}),
			blockNumber: LAST_FINALIZED_BLOCK_NUMBER,
		})
		.result()

	const task = decodeFunctionResult({
		abi: TASK_REGISTRY_ABI,
		functionName: 'getTask',
		data: bytesToHex(callResult.data),
	}) as {
		requester: Address
		agent: Address
		agentENSNode: Hex
		specHash: Hex
		taskSpec: string
		reward: bigint
		deadline: bigint
		status: number
		resultHash: Hex
	}

	const spec = JSON.parse(task.taskSpec) as TransferSpec
	if (spec.type !== 'transfer') {
		throw new Error(`Unsupported task type for verification: ${spec.type}`)
	}

	// ── Confidential portion: fetch the agent's actual on-chain execution
	// data and run the comparison against the requester's verification
	// criteria entirely inside the enclave. Only the verdict crosses back out.
	const txData = rpcCall<{ to: string | null; value: string } | null>(runtime, 'eth_getTransactionByHash', [
		task.resultHash,
	])
	const receipt = rpcCall<{ status: string } | null>(runtime, 'eth_getTransactionReceipt', [task.resultHash])

	if (!txData || !receipt) {
		throw new Error(`resultHash ${task.resultHash} is not a known transaction`)
	}

	const { passed, reason } = verifyTransferSpec(spec, txData, receipt.status)

	// Logs are for simulation debugging only and must be removed before any
	// production deployment - anything logged leaves the enclave.
	runtime.log(`Verification complete for task ${taskId}: passed=${passed} (${reason})`)

	// ── Cross back to the DON with only the conclusion - never the raw
	// transaction data or the verification criteria that produced it.
	const reportRuntime = runtime.usingTheDons()
	const encodedPayload = encodeAbiParameters(parseAbiParameters('uint256 taskId, bool passed'), [taskId, passed])

	reportRuntime
		.report({
			encodedPayload: hexToBase64(encodedPayload),
			encoderName: 'evm',
			signingAlgo: 'ecdsa',
			hashingAlgo: 'keccak256',
		})
		.result()

	// The signed report is a normal CRE report at this point. Delivering it
	// on-chain would go through evmClient.writeReport(reportRuntime, report)
	// to a receiver implementing Chainlink's IReceiver/KeystoneForwarder
	// interface - out of scope here; see CLAUDE.md for why (VerificationOracle
	// uses a simpler trusted-address gate instead, per issue #12's Option 1).
	return `Task ${taskId}: ${passed ? 'PASSED' : 'FAILED'} (${reason})`
}

// ─── Workflow Init ──────────────────────────────────────────
export function initWorkflow(config: Config) {
	const network = getNetwork({ chainFamily: 'evm', chainSelectorName: config.chainSelectorName })
	if (!network) {
		throw new Error(`Unknown chain selector name: ${config.chainSelectorName}`)
	}
	const evmClient = new cre.capabilities.EVMClient(network.chainSelector.selector)

	return [
		// ── Register a TEE handler for TaskRegistry's ResultSubmitted event.
		// AWS Nitro in us-west-2 is currently the only registered TEE type/region.
		cre.handlerInTee(
			evmClient.logTrigger(
				logTriggerConfig({
					addresses: [config.taskRegistryAddress as Hex],
					topics: [[RESULT_SUBMITTED_TOPIC0]],
				}),
			),
			onResultSubmitted,
			[{ tee: 'nitro', regions: ['us-west-2'] }],
		),
	]
}
