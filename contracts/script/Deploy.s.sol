// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {TaskRegistry} from "../src/TaskRegistry.sol";
import {VerificationOracle} from "../src/VerificationOracle.sol";

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

        // AgentRegistry (Task 1.4) added next, then:
        // oracle.setAgentRegistry(address(agentRegistry));

        vm.stopBroadcast();
    }
}
