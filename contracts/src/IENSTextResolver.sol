// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice Minimal slice of ENSv2's PermissionedResolver that AgentRegistry needs to
///         write trust-score text records.
interface IENSTextResolver {
    function setText(bytes32 node, string calldata key, string calldata value) external;
    function text(bytes32 node, string calldata key) external view returns (string memory);
}
