// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {TaskRegistry} from "../src/TaskRegistry.sol";
import {VerificationOracle} from "../src/VerificationOracle.sol";
import {AgentRegistry} from "../src/AgentRegistry.sol";

contract VerificationOracleTest is Test {
    TaskRegistry registry;
    VerificationOracle oracle;
    AgentRegistry agentRegistry;

    address owner = makeAddr("owner");
    address requester = makeAddr("requester");
    address agent = makeAddr("agent");
    address creDON = makeAddr("creDON");

    bytes32 constant ENS_NODE = keccak256("agent1.prove.eth");
    string constant SPEC = '{"type":"transfer","token":"ETH","amount":"0.01","to":"0xabc"}';

    function setUp() public {
        vm.startPrank(owner);
        registry = new TaskRegistry();
        oracle = new VerificationOracle(address(registry), creDON);
        registry.setVerificationOracle(address(oracle));

        agentRegistry = new AgentRegistry();
        agentRegistry.setScoreUpdater(address(oracle));
        agentRegistry.registerAgent(agent);
        oracle.setAgentRegistry(address(agentRegistry));
        vm.stopPrank();

        vm.deal(requester, 10 ether);
    }

    function _createAndExecuteTask() internal returns (uint256 id) {
        vm.prank(requester);
        id = registry.createTask{value: 1 ether}(ENS_NODE, SPEC, block.timestamp + 1 days);

        vm.prank(agent);
        registry.submitResult(id, keccak256("proof"));
    }

    // --- constructor ---

    function test_Constructor_RevertsWithZeroTaskRegistry() public {
        vm.expectRevert("taskRegistry required");
        new VerificationOracle(address(0), creDON);
    }

    function test_Constructor_SetsTaskRegistryAndCreDON() public view {
        assertEq(address(oracle.taskRegistry()), address(registry));
        assertEq(oracle.creDON(), creDON);
    }

    // --- admin ---

    function test_SetCreDON_UpdatesAddress() public {
        address newDON = makeAddr("newDON");
        vm.prank(owner);
        oracle.setCreDON(newDON);
        assertEq(oracle.creDON(), newDON);
    }

    function test_SetCreDON_RevertsForNonOwner() public {
        vm.prank(requester);
        vm.expectRevert();
        oracle.setCreDON(makeAddr("newDON"));
    }

    function test_SetAgentRegistry_UpdatesAddress() public {
        address registry_ = makeAddr("agentRegistry");
        vm.prank(owner);
        oracle.setAgentRegistry(registry_);
        assertEq(oracle.agentRegistry(), registry_);
    }

    function test_SetAgentRegistry_RevertsForNonOwner() public {
        vm.prank(requester);
        vm.expectRevert();
        oracle.setAgentRegistry(makeAddr("agentRegistry"));
    }

    // --- postVerification ---

    function test_PostVerification_PassedPaysAgent() public {
        uint256 id = _createAndExecuteTask();

        uint256 agentBefore = agent.balance;
        vm.prank(creDON);
        oracle.postVerification(id, true, "evidence");

        assertEq(agent.balance, agentBefore + 1 ether);
        TaskRegistry.Task memory t = registry.getTask(id);
        assertEq(uint256(t.status), uint256(TaskRegistry.Status.Paid));

        AgentRegistry.Agent memory a = agentRegistry.getAgent(ENS_NODE);
        assertEq(a.totalTasks, 1);
        assertEq(a.passedTasks, 1);
        assertEq(agentRegistry.trustScore(ENS_NODE), 1e18);
    }

    function test_PostVerification_FailedRefundsRequester() public {
        uint256 id = _createAndExecuteTask();

        uint256 requesterBefore = requester.balance;
        vm.prank(creDON);
        oracle.postVerification(id, false, "evidence");

        assertEq(requester.balance, requesterBefore + 1 ether);
        TaskRegistry.Task memory t = registry.getTask(id);
        assertEq(uint256(t.status), uint256(TaskRegistry.Status.Failed));

        AgentRegistry.Agent memory a = agentRegistry.getAgent(ENS_NODE);
        assertEq(a.totalTasks, 1);
        assertEq(a.failedTasks, 1);
        assertEq(agentRegistry.trustScore(ENS_NODE), 0);
    }

    function test_PostVerification_EmitsEvent() public {
        uint256 id = _createAndExecuteTask();

        vm.expectEmit(true, true, true, true);
        emit VerificationOracle.VerificationPosted(id, true, "evidence");

        vm.prank(creDON);
        oracle.postVerification(id, true, "evidence");
    }

    function test_PostVerification_RevertsIfNotCreDON() public {
        uint256 id = _createAndExecuteTask();

        vm.prank(agent);
        vm.expectRevert("only CRE DON");
        oracle.postVerification(id, true, "evidence");
    }

    function test_PostVerification_RevertsIfTaskNotExecuted() public {
        vm.prank(requester);
        uint256 id = registry.createTask{value: 1 ether}(ENS_NODE, SPEC, block.timestamp + 1 days);

        vm.prank(creDON);
        vm.expectRevert("not executed");
        oracle.postVerification(id, true, "evidence");
    }

    function test_PostVerification_RevertsOnDoubleVerification() public {
        uint256 id = _createAndExecuteTask();

        vm.prank(creDON);
        oracle.postVerification(id, true, "evidence");

        vm.prank(creDON);
        vm.expectRevert("not executed");
        oracle.postVerification(id, true, "evidence again");
    }
}
