// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {TaskRegistry} from "./TaskRegistry.sol";

/// @title VerificationOracle
/// @notice Receives the pass/fail attestation for a task and settles it on
///         TaskRegistry. In the full design the caller is the Chainlink CRE DON,
///         which compares the task spec against The Graph subgraph inside a TEE
contract VerificationOracle is Ownable {
    TaskRegistry public immutable taskRegistry;

    /// @notice Address authorized to call {postVerification} (the CRE DON).
    address public creDON;

    /// @notice AgentRegistry to update agents scores
    address public agentRegistry;

    event VerificationPosted(uint256 indexed taskId, bool passed, bytes attestation);
    event CreDONUpdated(address indexed creDON);
    event AgentRegistryUpdated(address indexed agentRegistry);

    constructor(address _taskRegistry, address _creDON) Ownable(msg.sender) {
        require(_taskRegistry != address(0), "taskRegistry required");
        taskRegistry = TaskRegistry(_taskRegistry);
        creDON = _creDON;
    }

    function setCreDON(address _creDON) external onlyOwner {
        creDON = _creDON;
        emit CreDONUpdated(_creDON);
    }

    function setAgentRegistry(address _agentRegistry) external onlyOwner {
        agentRegistry = _agentRegistry;
        emit AgentRegistryUpdated(_agentRegistry);
    }

    /// @notice Post a verification result for a task. Settles the reward via
    ///         TaskRegistry.completeTask, which also guards against re-verifying a
    ///         task that isn't in the Executed state.
    /// @param attestation Opaque evidence blob from the CRE workflow (e.g: a hash
    ///        of the subgraph data it compared against).
    function postVerification(uint256 taskId, bool passed, bytes calldata attestation) external {
        require(msg.sender == creDON, "only CRE DON");

        taskRegistry.completeTask(taskId, passed);

        // TODO(Task 1.4): once AgentRegistry exists, update the agent's trust score
        // here, e.g. IAgentRegistry(agentRegistry).recordResult(agentENSNode, passed).

        emit VerificationPosted(taskId, passed, attestation);
    }
}
