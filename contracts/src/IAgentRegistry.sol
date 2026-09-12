// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice Minimal interface VerificationOracle needs to update an agent's trust
///         score after settling a task.
interface IAgentRegistry {
    function recordResult(bytes32 ensNode, bool passed) external;
}
