// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {AgentRegistry} from "../src/AgentRegistry.sol";
import {IENSTextResolver} from "../src/IENSTextResolver.sol";

/// @dev Trivial stand-in for a real ENSv2 resolver, used only to verify AgentRegistry
///      calls setText with the right node/key/value - not a model of ENSv2's actual
///      access control. Real ENSv2 behavior is covered by the Sepolia fork test.
contract MockTextResolver is IENSTextResolver {
    mapping(bytes32 => mapping(string => string)) private _texts;

    function setText(bytes32 node, string calldata key, string calldata value) external {
        _texts[node][key] = value;
    }

    function text(bytes32 node, string calldata key) external view returns (string memory) {
        return _texts[node][key];
    }
}

contract AgentRegistryTest is Test {
    AgentRegistry registry;

    address owner = makeAddr("owner");
    address scoreUpdater = makeAddr("scoreUpdater");
    address agent1 = makeAddr("agent1");
    address agent2 = makeAddr("agent2");

    // Independently computed standard ENS namehash (not reused from AgentRegistry's own
    // helper), so this test actually verifies the formula, not just self-consistency.
    // Cross-checked against `cast namehash "agent1.prove.eth"`.
    bytes32 constant ETH_NODE = keccak256(abi.encodePacked(bytes32(0), keccak256(bytes("eth"))));
    bytes32 constant PROVE_NODE = keccak256(abi.encodePacked(ETH_NODE, keccak256(bytes("prove"))));
    bytes32 constant AGENT1_NODE = keccak256(abi.encodePacked(PROVE_NODE, keccak256(bytes("agent1"))));
    bytes32 constant AGENT2_NODE = keccak256(abi.encodePacked(PROVE_NODE, keccak256(bytes("agent2"))));

    function setUp() public {
        vm.startPrank(owner);
        registry = new AgentRegistry();
        registry.setScoreUpdater(scoreUpdater);
        vm.stopPrank();
    }

    // --- registerAgent ---

    function test_RegisterAgent_SequentialLabels() public {
        vm.startPrank(owner);
        (bytes32 node1, uint256 id1) = registry.registerAgent(agent1);
        (bytes32 node2, uint256 id2) = registry.registerAgent(agent2);
        vm.stopPrank();

        assertEq(id1, 1);
        assertEq(id2, 2);
        assertEq(node1, AGENT1_NODE);
        assertEq(node2, AGENT2_NODE);
        assertEq(registry.agentCount(), 2);

        AgentRegistry.Agent memory a = registry.getAgent(node1);
        assertEq(a.addr, agent1);
        assertEq(a.ensName, "agent1.prove.eth");
        assertEq(a.totalTasks, 0);
    }

    function test_RegisterAgent_RevertsForNonOwner() public {
        vm.prank(agent1);
        vm.expectRevert();
        registry.registerAgent(agent1);
    }

    function test_RegisterAgent_RevertsForZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert("agent required");
        registry.registerAgent(address(0));
    }

    // --- recordResult ---

    function test_RecordResult_RevertsForNonScoreUpdater() public {
        vm.prank(owner);
        (bytes32 node,) = registry.registerAgent(agent1);

        vm.prank(agent1);
        vm.expectRevert("only score updater");
        registry.recordResult(node, true);
    }

    function test_RecordResult_RevertsForUnknownAgent() public {
        vm.prank(scoreUpdater);
        vm.expectRevert("unknown agent");
        registry.recordResult(keccak256("nope"), true);
    }

    function test_RecordResult_AccumulatesCounts() public {
        vm.prank(owner);
        (bytes32 node,) = registry.registerAgent(agent1);

        vm.startPrank(scoreUpdater);
        registry.recordResult(node, true);
        registry.recordResult(node, true);
        registry.recordResult(node, false);
        vm.stopPrank();

        AgentRegistry.Agent memory a = registry.getAgent(node);
        assertEq(a.totalTasks, 3);
        assertEq(a.passedTasks, 2);
        assertEq(a.failedTasks, 1);
    }

    // --- trustScore ---

    function test_TrustScore_ZeroWhenNoTasks() public {
        vm.prank(owner);
        (bytes32 node,) = registry.registerAgent(agent1);

        assertEq(registry.trustScore(node), 0);
    }

    function test_TrustScore_FullPassRate() public {
        vm.prank(owner);
        (bytes32 node,) = registry.registerAgent(agent1);

        vm.prank(scoreUpdater);
        registry.recordResult(node, true);

        assertEq(registry.trustScore(node), 1e18);
    }

    function test_TrustScore_FullFailRate() public {
        vm.prank(owner);
        (bytes32 node,) = registry.registerAgent(agent1);

        vm.prank(scoreUpdater);
        registry.recordResult(node, false);

        assertEq(registry.trustScore(node), 0);
    }

    function test_TrustScore_PartialPassRate() public {
        vm.prank(owner);
        (bytes32 node,) = registry.registerAgent(agent1);

        vm.startPrank(scoreUpdater);
        registry.recordResult(node, true);
        registry.recordResult(node, true);
        registry.recordResult(node, false);
        registry.recordResult(node, false);
        vm.stopPrank();

        assertEq(registry.trustScore(node), 0.5e18);
    }

    // --- admin ---

    function test_SetScoreUpdater_RevertsForNonOwner() public {
        vm.prank(agent1);
        vm.expectRevert();
        registry.setScoreUpdater(agent1);
    }

    function test_SetResolver_RevertsForNonOwner() public {
        vm.prank(agent1);
        vm.expectRevert();
        registry.setResolver(address(1));
    }

    // --- ENS mirroring ---

    function test_RecordResult_SkipsENSWriteWhenResolverUnset() public {
        // resolver defaults to address(0); if AgentRegistry tried to call it,
        // this would revert (no code there). Passing confirms it's skipped.
        vm.prank(owner);
        (bytes32 node,) = registry.registerAgent(agent1);

        vm.prank(scoreUpdater);
        registry.recordResult(node, true);

        assertEq(registry.trustScore(node), 1e18);
    }

    function test_RecordResult_WritesTextRecordsWhenResolverSet() public {
        MockTextResolver resolver = new MockTextResolver();
        vm.prank(owner);
        registry.setResolver(address(resolver));

        vm.prank(owner);
        (bytes32 node,) = registry.registerAgent(agent1);

        vm.startPrank(scoreUpdater);
        registry.recordResult(node, true);
        registry.recordResult(node, true);
        registry.recordResult(node, false);
        vm.stopPrank();

        assertEq(resolver.text(node, "com.prove.trustScore"), "66");
        assertEq(resolver.text(node, "com.prove.totalTasks"), "3");
    }
}
