// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IENSTextResolver} from "./IENSTextResolver.sol";

/// @title AgentRegistry
/// @notice Tracks agent identity and trust score for the PROVE protocol. Agents are
///         referenced by `ensNode`, the real ENSv2 namehash of `agent<N>.prove.eth`
///         (see issue #4 for how that subname gets minted). This contract is the
///         source of truth for trust score regardless of ENS: if `resolver` is unset,
///         it just doesn't mirror to ENS 
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

    /// @dev Namehash of "eth", then "prove.eth" - the fixed parent for every agent
    ///      subname. Computed once at compile time (both inputs are literals).
    bytes32 private constant ETH_NODE = keccak256(abi.encodePacked(bytes32(0), keccak256(bytes("eth"))));
    bytes32 private constant PROVE_NODE = keccak256(abi.encodePacked(ETH_NODE, keccak256(bytes("prove"))));

    /// @notice Only this address may call {recordResult} (the VerificationOracle).
    address public scoreUpdater;

    /// @notice Real ENSv2 resolver holding agent text records. address(0) = ENS
    ///         mirroring disabled (this contract's own storage is still authoritative).
    address public resolver;

    uint256 public agentCount;
    mapping(bytes32 => Agent) public agents; // ensNode => Agent

    event AgentRegistered(uint256 indexed agentId, bytes32 indexed ensNode, address indexed agentAddress);
    event ResultRecorded(bytes32 indexed ensNode, bool passed, uint256 totalTasks, uint256 passedTasks);
    event ScoreUpdaterUpdated(address indexed scoreUpdater);
    event ResolverUpdated(address indexed resolver);

    constructor() Ownable(msg.sender) {}

    // --- admin ---

    function setScoreUpdater(address _scoreUpdater) external onlyOwner {
        scoreUpdater = _scoreUpdater;
        emit ScoreUpdaterUpdated(_scoreUpdater);
    }

    /// @notice Point at a real ENSv2 resolver to start mirroring trust scores there.
    ///         This contract must already hold ROLE_SET_TEXT on the resolver's
    ///         ROOT_RESOURCE (granted externally)
    function setResolver(address _resolver) external onlyOwner {
        resolver = _resolver;
        emit ResolverUpdated(_resolver);
    }

    // --- registration ---

    /// @notice The real ENSv2 namehash of "agent<agentId>.prove.eth".
    function agentEnsNode(uint256 agentId) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(PROVE_NODE, keccak256(bytes(string.concat("agent", agentId.toString())))));
    }

    /// @notice Register a new agent under a sequential label (agent1, agent2, ...).
    /// @dev `ensNode` is the real ENS namehash - the corresponding subname must
    ///      already be minted under prove.eth for ENS mirroring to work (issue #4).
    function registerAgent(address agentAddress) external onlyOwner returns (bytes32 ensNode, uint256 agentId) {
        require(agentAddress != address(0), "agent required");

        agentId = ++agentCount;
        ensNode = agentEnsNode(agentId);
        require(agents[ensNode].addr == address(0), "already registered");

        agents[ensNode] = Agent({
            ensNode: ensNode,
            addr: agentAddress,
            ensName: string.concat("agent", agentId.toString(), ".prove.eth"),
            totalTasks: 0,
            passedTasks: 0,
            failedTasks: 0
        });

        emit AgentRegistered(agentId, ensNode, agentAddress);
    }

    // --- score updates ---

    /// @notice Record a task outcome for an agent. Called by VerificationOracle after
    ///         it settles a task. Mirrors the updated trust score to ENS if a
    ///         resolver is configured.
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

        if (resolver != address(0)) {
            uint256 percent = (agent.passedTasks * 100) / agent.totalTasks;
            IENSTextResolver(resolver).setText(ensNode, "com.prove.trustScore", percent.toString());
            IENSTextResolver(resolver).setText(ensNode, "com.prove.totalTasks", agent.totalTasks.toString());
        }
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
