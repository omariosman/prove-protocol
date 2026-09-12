// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/// @title AgentRegistry
/// @notice Tracks agent identity and trust score for the PROVE protocol. Agents are
///         referenced by an `ensNode` key: today that's a placeholder
///         (keccak256("agentN.prove.eth")), to be replaced by the real ENSv2 namehash
///         once the agent subname is actually minted on Sepolia (see issues #4/#5).
///         This contract works standalone either way - it's the source of truth for
///         trust score regardless of whether the ENS mirror is wired up.
contract AgentRegistry is Ownable {
    using Strings for uint256;

    struct Agent {
        bytes32 ensNode;
        address addr;
        string ensName; // e.g. "agent1.prove.eth", for humans/tooling
        uint256 totalTasks;
        uint256 passedTasks;
        uint256 failedTasks;
    }

    uint256 private constant WAD = 1e18;

    /// @notice Only this address may call {recordResult} (the VerificationOracle).
    address public scoreUpdater;

    uint256 public agentCount;
    mapping(bytes32 => Agent) public agents; // ensNode => Agent

    event AgentRegistered(uint256 indexed agentId, bytes32 indexed ensNode, address indexed agentAddress);
    event ResultRecorded(bytes32 indexed ensNode, bool passed, uint256 totalTasks, uint256 passedTasks);
    event ScoreUpdaterUpdated(address indexed scoreUpdater);

    constructor() Ownable(msg.sender) {}

    // --- admin ---

    function setScoreUpdater(address _scoreUpdater) external onlyOwner {
        scoreUpdater = _scoreUpdater;
        emit ScoreUpdaterUpdated(_scoreUpdater);
    }

    // --- registration ---

    /// @notice Register a new agent under a sequential label (agent1, agent2, ...).
    /// @dev `ensNode` is a placeholder key (keccak256 of the intended name) until the
    ///      real ENS subname is minted - see issue #4/#5.
    function registerAgent(address agentAddress) external onlyOwner returns (bytes32 ensNode, uint256 agentId) {
        require(agentAddress != address(0), "agent required");

        agentId = ++agentCount;
        string memory ensName = string.concat("agent", agentId.toString(), ".prove.eth");
        ensNode = keccak256(bytes(ensName));
        require(agents[ensNode].addr == address(0), "already registered");

        agents[ensNode] = Agent({
            ensNode: ensNode, addr: agentAddress, ensName: ensName, totalTasks: 0, passedTasks: 0, failedTasks: 0
        });

        emit AgentRegistered(agentId, ensNode, agentAddress);
    }

    // --- score updates ---

    /// @notice Record a task outcome for an agent. Called by VerificationOracle after
    ///         it settles a task.
    function recordResult(bytes32 ensNode, bool passed) external {
        require(msg.sender == scoreUpdater, "only score updater");
        Agent storage agent = agents[ensNode];
        require(agent.addr != address(0), "unknown agent");

        agent.totalTasks += 1;
        if (passed) {
            agent.passedTasks += 1;
        } else {
            agent.failedTasks += 1;
        }

        emit ResultRecorded(ensNode, passed, agent.totalTasks, agent.passedTasks);
    }

    // --- views ---

    /// @notice Trust score as a wad (1e18 = 100%). Returns 0 if the agent has no tasks yet.
    function trustScore(bytes32 ensNode) external view returns (uint256) {
        Agent storage agent = agents[ensNode];
        if (agent.totalTasks == 0) {
            return 0;
        }
        return (agent.passedTasks * WAD) / agent.totalTasks;
    }

    function getAgent(bytes32 ensNode) external view returns (Agent memory) {
        return agents[ensNode];
    }
}
