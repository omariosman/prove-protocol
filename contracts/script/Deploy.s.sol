// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";

/// @notice Deploys the PROVE protocol contracts to the target network.
/// Filled in during Task 1.2–1.4. Run with:
///   forge script script/Deploy.s.sol --rpc-url sepolia --broadcast --verify
contract Deploy is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(pk);

        // TaskRegistry, VerificationOracle, AgentRegistry deployed here.
        console.log("Nothing to deploy yet - see Task 1.2");

        vm.stopBroadcast();
    }
}
