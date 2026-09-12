// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {TaskRegistry} from "../src/TaskRegistry.sol";

/// @notice Deploys the PROVE protocol contracts.
///   forge script script/Deploy.s.sol --rpc-url sepolia --broadcast --verify
/// Requires contracts/.env with PRIVATE_KEY, SEPOLIA_RPC_URL, ETHERSCAN_API_KEY.
contract Deploy is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(pk);

        TaskRegistry registry = new TaskRegistry();
        console.log("TaskRegistry:", address(registry));

        // VerificationOracle (Task 1.3) and AgentRegistry (Task 1.4) added next,
        // then: registry.setVerificationOracle(address(oracle));

        vm.stopBroadcast();
    }
}
