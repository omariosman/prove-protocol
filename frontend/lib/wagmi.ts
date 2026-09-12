import { createConfig, http } from 'wagmi'
import { sepolia } from 'wagmi/chains'
import { injected } from 'wagmi/connectors/injected'
import { SEPOLIA_RPC_URL } from './contracts'

export const wagmiConfig = createConfig({
	chains: [sepolia],
	connectors: [injected()],
	transports: {
		[sepolia.id]: http(SEPOLIA_RPC_URL),
	},
})

declare module 'wagmi' {
	interface Register {
		config: typeof wagmiConfig
	}
}
