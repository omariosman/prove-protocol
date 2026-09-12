// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {TaskRegistry} from "../src/TaskRegistry.sol";
import {VerificationOracle} from "../src/VerificationOracle.sol";
import {AgentRegistry} from "../src/AgentRegistry.sol";

/// @notice Deploys the PROVE protocol contracts.
///   forge script script/Deploy.s.sol --rpc-url sepolia --broadcast --verify
/// Requires contracts/.env with PRIVATE_KEY, SEPOLIA_RPC_URL, ETHERSCAN_API_KEY.
/// Optional: CRE_DON_ADDRESS (defaults to the deployer if unset - fine for the PoC,
/// where the "oracle" may just be a trusted script rather than a real CRE DON).
contract Deploy is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);
        address creDON = vm.envOr("CRE_DON_ADDRESS", deployer);

        vm.startBroadcast(pk);

        TaskRegistry registry = new TaskRegistry();
        console.log("TaskRegistry:", address(registry));

        VerificationOracle oracle = new VerificationOracle(address(registry), creDON);
        console.log("VerificationOracle:", address(oracle));
        console.log("  creDON:", creDON);

        registry.setVerificationOracle(address(oracle));

        AgentRegistry agentRegistry = new AgentRegistry();
        console.log("AgentRegistry:", address(agentRegistry));

        oracle.setAgentRegistry(address(agentRegistry));
        agentRegistry.setScoreUpdater(address(oracle));

        // Real ENSv2 agent subname registration (issues #4/#5) is a separate script
        // (script/RegisterAgentENS.s.sol) - agentRegistry.registerAgent() is called
        // per-agent there, not as part of this base deploy.

        vm.stopBroadcast();
    }
}
