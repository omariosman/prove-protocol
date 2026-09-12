// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {AgentRegistry} from "../src/AgentRegistry.sol";
import {IENSTextResolver} from "../src/IENSTextResolver.sol";

/// @notice Exercises AgentRegistry against the *real* deployed ENSv2 contracts on a
///         Sepolia fork - real bytecode, real Enhanced Access Control, real
///         `prove.eth` / `agent1.prove.eth` state from issue #4. Not meaningfully
///         testable against mocks (see issue #5). Requires SEPOLIA_RPC_URL in .env.
contract AgentRegistryENSForkTest is Test {
    address constant RESOLVER = 0x7add7bD84C9DB30800711a6020bA328Ef73b9A35;
    address constant REAL_DEPLOYER = 0x27cb1F440476D2bbC1F0e4bAa05046bF20ba4e34;
    address constant AGENT1_OWNER = 0x9E61c0fD51fD418B1dA5976D552A08269F955C94;

    // PermissionedResolverLib (contracts-v2/src/resolver/libraries/PermissionedResolverLib.sol)
    uint256 constant ROLE_SET_TEXT = 1 << 4;
    uint256 constant ROLE_SET_TEXT_ADMIN = ROLE_SET_TEXT << 128;

    AgentRegistry registry;
    address scoreUpdater = makeAddr("scoreUpdater");

    function setUp() public {
        vm.createSelectFork(vm.envString("SEPOLIA_RPC_URL"));

        registry = new AgentRegistry();
        registry.setScoreUpdater(scoreUpdater);
        registry.setResolver(RESOLVER);

        // REAL_DEPLOYER genuinely holds ROLE_SET_TEXT_ADMIN on RESOLVER's ROOT_RESOURCE
        // on real Sepolia (granted in issue #4) - the fork carries that state, so this
        // grant succeeds exactly as it would in production.
        vm.prank(REAL_DEPLOYER);
        (bool ok,) = RESOLVER.call(
            abi.encodeWithSignature(
                "grantRootRoles(uint256,address)", ROLE_SET_TEXT | ROLE_SET_TEXT_ADMIN, address(registry)
            )
        );
        require(ok, "grantRootRoles failed");
    }

    function test_RegisterAgent_ProducesRealAgent1Node() public {
        (bytes32 node,) = registry.registerAgent(AGENT1_OWNER);
        // agent1.prove.eth was minted for real in issue #4, under this exact node.
        assertEq(node, cast_namehash());
    }

    function test_RecordResult_WritesRealTextRecordsOnResolver() public {
        (bytes32 node,) = registry.registerAgent(AGENT1_OWNER);

        vm.prank(scoreUpdater);
        registry.recordResult(node, true);

        assertEq(IENSTextResolver(RESOLVER).text(node, "com.prove.trustScore"), "100");
        assertEq(IENSTextResolver(RESOLVER).text(node, "com.prove.totalTasks"), "1");
    }

    function test_RecordResult_UpdatesRealTextRecordsAcrossMultipleCalls() public {
        (bytes32 node,) = registry.registerAgent(AGENT1_OWNER);

        vm.startPrank(scoreUpdater);
        registry.recordResult(node, true);
        registry.recordResult(node, false);
        vm.stopPrank();

        assertEq(IENSTextResolver(RESOLVER).text(node, "com.prove.trustScore"), "50");
        assertEq(IENSTextResolver(RESOLVER).text(node, "com.prove.totalTasks"), "2");
    }

    /// @dev Standard ENS namehash for "agent1.prove.eth", computed independently of
    ///      AgentRegistry's own helper - cross-checked against `cast namehash`.
    function cast_namehash() internal pure returns (bytes32) {
        bytes32 ethNode = keccak256(abi.encodePacked(bytes32(0), keccak256(bytes("eth"))));
        bytes32 proveNode = keccak256(abi.encodePacked(ethNode, keccak256(bytes("prove"))));
        return keccak256(abi.encodePacked(proveNode, keccak256(bytes("agent1"))));
    }
}
