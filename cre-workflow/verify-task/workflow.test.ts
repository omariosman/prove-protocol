import { describe, expect, test } from 'bun:test'
import { initWorkflow, verifyTransferSpec } from './workflow'

const SPEC = {
	type: 'transfer' as const,
	token: 'ETH',
	amount: '0.0002',
	to: '0x27cb1F440476D2bbC1F0e4bAa05046bF20ba4e34',
	deadline: 1789237656,
}

// Real values from the Task 1.5 Sepolia demo (tx 0x51072cbc...) - the actual
// transfer PROVE's verification is checking against.
const REAL_TX = { to: '0x27cb1F440476D2bbC1F0e4bAa05046bF20ba4e34', value: '200000000000000' } // 0.0002 ETH in wei
const REAL_RECEIPT_STATUS = '0x1'

describe('verifyTransferSpec', () => {
	test('passes when recipient, amount, and status all match the spec', () => {
		const result = verifyTransferSpec(SPEC, REAL_TX, REAL_RECEIPT_STATUS)
		expect(result).toEqual({ passed: true, reason: 'transfer matches spec' })
	})

	test('fails when the transaction reverted', () => {
		const result = verifyTransferSpec(SPEC, REAL_TX, '0x0')
		expect(result.passed).toBe(false)
		expect(result.reason).toBe('transaction reverted')
	})

	test('fails when the recipient does not match', () => {
		const result = verifyTransferSpec(SPEC, { ...REAL_TX, to: '0x0000000000000000000000000000000000dEaD' }, REAL_RECEIPT_STATUS)
		expect(result.passed).toBe(false)
		expect(result.reason).toBe('recipient does not match spec')
	})

	test('recipient match is case-insensitive', () => {
		const result = verifyTransferSpec(SPEC, { ...REAL_TX, to: REAL_TX.to.toLowerCase() }, REAL_RECEIPT_STATUS)
		expect(result.passed).toBe(true)
	})

	test('fails when the amount does not match', () => {
		const result = verifyTransferSpec(SPEC, { ...REAL_TX, value: '1' }, REAL_RECEIPT_STATUS)
		expect(result.passed).toBe(false)
		expect(result.reason).toBe('amount does not match spec')
	})

	test('fails when the transaction has no recipient (contract creation)', () => {
		const result = verifyTransferSpec(SPEC, { ...REAL_TX, to: null }, REAL_RECEIPT_STATUS)
		expect(result.passed).toBe(false)
		expect(result.reason).toBe('recipient does not match spec')
	})
})

describe('initWorkflow', () => {
	test('registers the EVM log handler with a Nitro TEE constraint', () => {
		const handlers = initWorkflow({
			taskRegistryAddress: '0x97b2702a20375Ff7E0Db05460e512545c47BbEB1',
			chainSelectorName: 'ethereum-testnet-sepolia',
			rpcUrl: 'https://ethereum-sepolia-rpc.publicnode.com',
		})

		expect(handlers).toHaveLength(1)
		// handlerInTee attaches TEE requirements; cre.handler does not.
		expect(handlers[0].requirements).toBeDefined()
	})

	test('throws for an unknown chain selector name', () => {
		expect(() =>
			initWorkflow({
				taskRegistryAddress: '0x97b2702a20375Ff7E0Db05460e512545c47BbEB1',
				chainSelectorName: 'not-a-real-chain',
				rpcUrl: 'https://example.com',
			}),
		).toThrow('Unknown chain selector name')
	})
})
