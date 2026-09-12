// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title TaskRegistry
/// @notice Core of the PROVE protocol. A requester posts a task with an ETH reward
///         held in escrow. An agent submits a result. The VerificationOracle then
///         reports pass/fail, which releases the reward to the agent or refunds the
///         requester.
contract TaskRegistry is Ownable, ReentrancyGuard {
    /// @dev Status strings used by the subgraph must match these names exactly:
    ///      Open -> Executed -> Verified -> Paid, or Failed.
    enum Status {
        Open,
        Executed,
        Verified,
        Paid,
        Failed
    }

    struct Task {
        address requester;
        address agent; // set when a result is submitted
        bytes32 agentENSNode; // ENSv2 node the requester wants to handle this
        bytes32 specHash; // keccak256(taskSpec)
        string taskSpec; // raw JSON spec
        uint256 reward; // wei in escrow (zeroed once paid/refunded)
        uint256 deadline; // unix timestamp; result must be submitted by then
        Status status;
        bytes32 resultHash; // agent's execution proof hash
    }

    /// @notice Only this address may call {completeTask}. Set once by the owner
    address public verificationOracle;

    uint256 public taskCount;
    mapping(uint256 => Task) public tasks;

    event TaskCreated(
        uint256 indexed taskId,
        address indexed requester,
        bytes32 indexed agentENSNode,
        bytes32 specHash,
        string taskSpec,
        uint256 reward,
        uint256 deadline
    );
    event ResultSubmitted(uint256 indexed taskId, address indexed agent, bytes32 resultHash);
    event TaskVerified(uint256 indexed taskId, bool passed);
    event RewardReleased(uint256 indexed taskId, address indexed agent, uint256 amount);
    event RewardRefunded(uint256 indexed taskId, address indexed requester, uint256 amount);
    event VerificationOracleUpdated(address indexed oracle);

    constructor() Ownable(msg.sender) {}

    // --- admin ---

    function setVerificationOracle(address oracle) external onlyOwner {
        verificationOracle = oracle;
        emit VerificationOracleUpdated(oracle);
    }

    // --- requester ---

    /// @notice Post a task. The ETH sent with the call becomes the reward.
    /// @param agentENSNode ENSv2 node of the agent expected to fulfil the task.
    /// @param taskSpec     JSON spec, e.g. {"type":"transfer","token":"ETH",...}.
    /// @param deadline     Unix timestamp the result must be submitted by.
    function createTask(bytes32 agentENSNode, string calldata taskSpec, uint256 deadline)
        external
        payable
        returns (uint256 taskId)
    {
        require(msg.value > 0, "reward required");
        require(deadline > block.timestamp, "deadline in past");

        bytes32 specHash = keccak256(bytes(taskSpec));
        taskId = ++taskCount;

        tasks[taskId] = Task({
            requester: msg.sender,
            agent: address(0),
            agentENSNode: agentENSNode,
            specHash: specHash,
            taskSpec: taskSpec,
            reward: msg.value,
            deadline: deadline,
            status: Status.Open,
            resultHash: bytes32(0)
        });

        emit TaskCreated(taskId, msg.sender, agentENSNode, specHash, taskSpec, msg.value, deadline);
    }

    /// @notice Refund an Open task whose deadline has passed with no submission.
    function reclaimExpired(uint256 taskId) external nonReentrant {
        Task storage t = tasks[taskId];
        require(t.status == Status.Open, "not open");
        require(block.timestamp > t.deadline, "not expired");
        _refundReward(taskId);
    }

    // --- agent ---

    /// @notice Agent marks a task as executed and attaches a proof hash.
    function submitResult(uint256 taskId, bytes32 resultHash) external {
        Task storage t = tasks[taskId];
        require(t.status == Status.Open, "not open");
        require(block.timestamp <= t.deadline, "past deadline");

        t.agent = msg.sender;
        t.resultHash = resultHash;
        t.status = Status.Executed;

        emit ResultSubmitted(taskId, msg.sender, resultHash);
    }

    // --- verification oracle ---

    /// @notice Called by the VerificationOracle with the pass/fail outcome.
    ///         Pass -> reward to agent. Fail -> refund to requester.
    function completeTask(uint256 taskId, bool passed) external nonReentrant {
        require(msg.sender == verificationOracle, "only oracle");
        Task storage t = tasks[taskId];
        require(t.status == Status.Executed, "not executed");

        t.status = Status.Verified;
        emit TaskVerified(taskId, passed);

        if (passed) {
            _releaseReward(taskId);
        } else {
            _refundReward(taskId);
        }
    }

    // --- internal ---

    function _releaseReward(uint256 taskId) internal {
        Task storage t = tasks[taskId];
        uint256 amount = t.reward;
        t.reward = 0;
        t.status = Status.Paid;

        (bool ok,) = t.agent.call{value: amount}("");
        require(ok, "transfer failed");

        emit RewardReleased(taskId, t.agent, amount);
    }

    function _refundReward(uint256 taskId) internal {
        Task storage t = tasks[taskId];
        uint256 amount = t.reward;
        t.reward = 0;
        t.status = Status.Failed;

        (bool ok,) = t.requester.call{value: amount}("");
        require(ok, "refund failed");

        emit RewardRefunded(taskId, t.requester, amount);
    }

    // --- views ---

    /// @notice Full task struct (the auto-generated mapping getter omits `taskSpec`
    ///         when compiled with some toolchains; this returns everything).
    function getTask(uint256 taskId) external view returns (Task memory) {
        return tasks[taskId];
    }
}
