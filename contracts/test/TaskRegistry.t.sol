// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {TaskRegistry} from "../src/TaskRegistry.sol";

contract TaskRegistryTest is Test {
    TaskRegistry registry;

    address owner = makeAddr("owner");
    address requester = makeAddr("requester");
    address agent = makeAddr("agent");
    address oracle = makeAddr("oracle");

    bytes32 constant ENS_NODE = keccak256("agent1.prove.eth");
    string constant SPEC = '{"type":"transfer","token":"ETH","amount":"0.01","to":"0xabc"}';

    function setUp() public {
        vm.prank(owner);
        registry = new TaskRegistry();

        vm.prank(owner);
        registry.setVerificationOracle(oracle);

        vm.deal(requester, 10 ether);
    }

    function _createTask(uint256 reward, uint256 deadline) internal returns (uint256 id) {
        vm.prank(requester);
        id = registry.createTask{value: reward}(ENS_NODE, SPEC, deadline);
    }

    // --- createTask ---

    function test_CreateTask_StoresFieldsAndEscrowsEth() public {
        uint256 deadline = block.timestamp + 1 days;
        uint256 id = _createTask(1 ether, deadline);

        assertEq(id, 1);
        assertEq(registry.taskCount(), 1);
        assertEq(address(registry).balance, 1 ether);

        TaskRegistry.Task memory t = registry.getTask(id);
        assertEq(t.requester, requester);
        assertEq(t.agent, address(0));
        assertEq(t.agentENSNode, ENS_NODE);
        assertEq(t.specHash, keccak256(bytes(SPEC)));
        assertEq(t.taskSpec, SPEC);
        assertEq(t.reward, 1 ether);
        assertEq(t.deadline, deadline);
        assertEq(uint256(t.status), uint256(TaskRegistry.Status.Open));
    }

    function test_CreateTask_RevertsWithoutReward() public {
        vm.prank(requester);
        vm.expectRevert("reward required");
        registry.createTask(ENS_NODE, SPEC, block.timestamp + 1 days);
    }

    function test_CreateTask_RevertsWithPastDeadline() public {
        vm.prank(requester);
        vm.expectRevert("deadline in past");
        registry.createTask{value: 1 ether}(ENS_NODE, SPEC, block.timestamp);
    }

    // --- submitResult ---

    function test_SubmitResult_MarksExecuted() public {
        uint256 id = _createTask(1 ether, block.timestamp + 1 days);

        vm.prank(agent);
        registry.submitResult(id, keccak256("proof"));

        TaskRegistry.Task memory t = registry.getTask(id);
        assertEq(t.agent, agent);
        assertEq(t.resultHash, keccak256("proof"));
        assertEq(uint256(t.status), uint256(TaskRegistry.Status.Executed));
    }

    function test_SubmitResult_RevertsIfNotOpen() public {
        uint256 id = _createTask(1 ether, block.timestamp + 1 days);
        vm.prank(agent);
        registry.submitResult(id, keccak256("proof"));

        vm.prank(agent);
        vm.expectRevert("not open");
        registry.submitResult(id, keccak256("proof2"));
    }

    function test_SubmitResult_RevertsAfterDeadline() public {
        uint256 id = _createTask(1 ether, block.timestamp + 1 days);
        vm.warp(block.timestamp + 2 days);

        vm.prank(agent);
        vm.expectRevert("past deadline");
        registry.submitResult(id, keccak256("proof"));
    }

    // --- completeTask ---

    function test_CompleteTask_PassedPaysAgent() public {
        uint256 id = _createTask(1 ether, block.timestamp + 1 days);
        vm.prank(agent);
        registry.submitResult(id, keccak256("proof"));

        uint256 agentBefore = agent.balance;
        vm.prank(oracle);
        registry.completeTask(id, true);

        assertEq(agent.balance, agentBefore + 1 ether);
        assertEq(address(registry).balance, 0);

        TaskRegistry.Task memory t = registry.getTask(id);
        assertEq(uint256(t.status), uint256(TaskRegistry.Status.Paid));
        assertEq(t.reward, 0);
    }

    function test_CompleteTask_FailedRefundsRequester() public {
        uint256 id = _createTask(1 ether, block.timestamp + 1 days);
        vm.prank(agent);
        registry.submitResult(id, keccak256("proof"));

        uint256 requesterBefore = requester.balance;
        vm.prank(oracle);
        registry.completeTask(id, false);

        assertEq(requester.balance, requesterBefore + 1 ether);
        assertEq(address(registry).balance, 0);

        TaskRegistry.Task memory t = registry.getTask(id);
        assertEq(uint256(t.status), uint256(TaskRegistry.Status.Failed));
    }

    function test_CompleteTask_RevertsIfNotOracle() public {
        uint256 id = _createTask(1 ether, block.timestamp + 1 days);
        vm.prank(agent);
        registry.submitResult(id, keccak256("proof"));

        vm.prank(agent);
        vm.expectRevert("only oracle");
        registry.completeTask(id, true);
    }

    function test_CompleteTask_RevertsIfNotExecuted() public {
        uint256 id = _createTask(1 ether, block.timestamp + 1 days);

        vm.prank(oracle);
        vm.expectRevert("not executed");
        registry.completeTask(id, true);
    }

    // --- reclaimExpired ---

    function test_ReclaimExpired_RefundsRequester() public {
        uint256 id = _createTask(1 ether, block.timestamp + 1 days);
        vm.warp(block.timestamp + 2 days);

        uint256 requesterBefore = requester.balance;
        registry.reclaimExpired(id);

        assertEq(requester.balance, requesterBefore + 1 ether);
        TaskRegistry.Task memory t = registry.getTask(id);
        assertEq(uint256(t.status), uint256(TaskRegistry.Status.Failed));
    }

    function test_ReclaimExpired_RevertsIfNotExpired() public {
        uint256 id = _createTask(1 ether, block.timestamp + 1 days);

        vm.expectRevert("not expired");
        registry.reclaimExpired(id);
    }

    function test_ReclaimExpired_RevertsIfAlreadyExecuted() public {
        uint256 id = _createTask(1 ether, block.timestamp + 1 days);
        vm.prank(agent);
        registry.submitResult(id, keccak256("proof"));
        vm.warp(block.timestamp + 2 days);

        vm.expectRevert("not open");
        registry.reclaimExpired(id);
    }

    // --- admin ---

    function test_SetVerificationOracle_RevertsForNonOwner() public {
        vm.prank(requester);
        vm.expectRevert();
        registry.setVerificationOracle(address(1));
    }

    // --- events ---

    function test_CreateTask_EmitsEvent() public {
        uint256 deadline = block.timestamp + 1 days;
        vm.expectEmit(true, true, true, true);
        emit TaskRegistry.TaskCreated(1, requester, ENS_NODE, keccak256(bytes(SPEC)), SPEC, 1 ether, deadline);
        _createTask(1 ether, deadline);
    }
}
