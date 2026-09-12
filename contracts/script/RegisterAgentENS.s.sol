// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";

/// @notice Registers `prove.eth` on ENSv2 Sepolia and mints `agent1.prove.eth` as a real
///         agent subname, per issue #4. This is a spike script, not app code - see
///         CLAUDE.md "ENSv2 integration notes" for how every address/interface here was
///         verified (pulled directly from ensdomains/contracts-v2 + ensdomains/verifiable-factory
///         source and live on-chain reads, not a summarized source).
///
/// Run in three phases (commit-reveal requires a real time gap between phases 2 and 3):
///   forge script script/RegisterAgentENS.s.sol --sig "deployInfra()" --rpc-url sepolia --broadcast
///   forge script script/RegisterAgentENS.s.sol --sig "mintApproveAndCommit()" --rpc-url sepolia --broadcast
///   (wait >= 60s, ENSv2's MIN_COMMITMENT_AGE on Sepolia)
///   forge script script/RegisterAgentENS.s.sol --sig "registerProveAndAgent(address)" <agentAddress> --rpc-url sepolia --broadcast
///
/// Requires contracts/.env with PRIVATE_KEY, SEPOLIA_RPC_URL.
interface IVerifiableFactory {
    function deployProxy(address implementation, uint256 salt, bytes memory data) external returns (address proxy);
}

interface IUserRegistry {
    function register(
        string memory label,
        address owner,
        address registry,
        address resolver,
        uint256 roleBitmap,
        uint64 expiry
    )
        external
        returns (uint256);
}

interface IPermissionedResolver {
    function setText(bytes32 node, string calldata key, string calldata value) external;
    function text(bytes32 node, string calldata key) external view returns (string memory);
}

interface IETHRegistrar {
    function commit(bytes32 commitment) external;
    function register(
        string calldata label,
        address owner,
        bytes32 secret,
        address subregistry,
        address resolver,
        uint64 duration,
        address paymentToken,
        bytes32 referrer
    )
        external
        returns (uint256);
    function makeCommitment(
        string calldata label,
        address owner,
        bytes32 secret,
        address subregistry,
        address resolver,
        uint64 duration,
        bytes32 referrer
    )
        external
        pure
        returns (bytes32);
    function isAvailable(string calldata label) external view returns (bool);
    function getRegisterPrice(string calldata label, uint64 duration, address paymentToken)
        external
        view
        returns (uint256 base, uint256 premium);
}

interface IMockERC20 {
    function mint(address to, uint256 amount) external;
    function approve(address spender, uint256 amount) external returns (bool);
}

contract RegisterAgentENS is Script {
    // Verified live on Sepolia 2026-09-12 - see CLAUDE.md "ENSv2 integration notes".
    address constant VERIFIABLE_FACTORY = 0x118Bc31A50d559F7015a8Da26d54B3b030CdB70F;
    address constant USER_REGISTRY_IMPL = 0x840Fa461059862Ea466A711E8C98c8dE732061C0;
    address constant PERMISSIONED_RESOLVER_IMPL = 0x7E4B2d59938930168024201752EE5503df402303;
    address constant ETH_REGISTRAR = 0xa4449a0dD2b83007553D9b1d28b583A46A805a30;
    address constant MOCK_USDC = 0xD3322B29a7BdEe707D1684676f149bf41Aa3422f;

    // RegistryRolesLib (contracts-v2/src/registry/libraries/RegistryRolesLib.sol)
    uint256 constant ROLE_REGISTRAR = 1 << 0;
    uint256 constant ROLE_REGISTRAR_ADMIN = ROLE_REGISTRAR << 128;
    uint256 constant ROLE_RENEW = 1 << 16;
    uint256 constant ROLE_RENEW_ADMIN = ROLE_RENEW << 128;
    uint256 constant ROLE_SET_RESOLVER = 1 << 24;
    uint256 constant ROLE_SET_RESOLVER_ADMIN = ROLE_SET_RESOLVER << 128;

    // PermissionedResolverLib (contracts-v2/src/resolver/libraries/PermissionedResolverLib.sol)
    uint256 constant ROLE_SET_TEXT = 1 << 4;
    uint256 constant ROLE_SET_TEXT_ADMIN = ROLE_SET_TEXT << 128;

    string constant LABEL = "prove";
    uint64 constant DURATION = 365 days;
    // Fixed on purpose: this is a testnet PoC, not a real commit-reveal front-running
    // defense scenario. A real deployment would randomize this.
    bytes32 constant SECRET = keccak256("prove-hackathon-secret-v1");

    string constant OUTPUT_PATH = "script/output/ens-deployment.sepolia.json";

    /// @notice Phase 1: deploy our own subregistry (for prove.eth's subnames) and our own
    ///         resolver, both as VerifiableFactory proxy clones of the shared ENSv2
    ///         implementations. Each is ours alone - the deployer gets ROOT_RESOURCE roles
    ///         on both, which is why a shared/already-initialized implementation can't be
    ///         used directly (confirmed live: PermissionedResolverImpl already has a
    ///         nonzero root role count on Sepolia, i.e. someone else's admin).
    function deployInfra() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        vm.startBroadcast(pk);

        uint256 registryRoles = ROLE_REGISTRAR | ROLE_REGISTRAR_ADMIN | ROLE_RENEW | ROLE_RENEW_ADMIN
            | ROLE_SET_RESOLVER | ROLE_SET_RESOLVER_ADMIN;
        address subregistry = IVerifiableFactory(VERIFIABLE_FACTORY).deployProxy(
            USER_REGISTRY_IMPL,
            uint256(keccak256("prove.eth-subregistry-v1")),
            abi.encodeWithSignature("initialize(address,uint256)", deployer, registryRoles)
        );
        console.log("prove.eth subregistry:", subregistry);

        uint256 resolverRoles = ROLE_SET_TEXT | ROLE_SET_TEXT_ADMIN;
        address resolver = IVerifiableFactory(VERIFIABLE_FACTORY).deployProxy(
            PERMISSIONED_RESOLVER_IMPL,
            uint256(keccak256("prove.eth-resolver-v1")),
            abi.encodeWithSignature("initialize(address,uint256,bytes[])", deployer, resolverRoles, new bytes[](0))
        );
        console.log("prove.eth resolver:", resolver);

        vm.stopBroadcast();

        string memory json = string.concat(
            '{"subregistry":"',
            vm.toString(subregistry),
            '","resolver":"',
            vm.toString(resolver),
            '"}'
        );
        vm.writeFile(OUTPUT_PATH, json);
        console.log("Saved addresses to", OUTPUT_PATH);
    }

    /// @notice Phase 2: mint enough MockUSDC to cover the registration price, approve the
    ///         registrar, and commit. Must wait >= MIN_COMMITMENT_AGE (60s on Sepolia)
    ///         before calling registerProveAndAgent.
    function mintApproveAndCommit() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);
        (address subregistry, address resolver) = _readInfra();

        (uint256 base, uint256 premium) =
            IETHRegistrar(ETH_REGISTRAR).getRegisterPrice(LABEL, DURATION, MOCK_USDC);
        uint256 price = base + premium;
        uint256 mintAmount = price * 2; // headroom
        console.log("Register price (USDC, 6dp):", price);

        vm.startBroadcast(pk);

        IMockERC20(MOCK_USDC).mint(deployer, mintAmount);
        IMockERC20(MOCK_USDC).approve(ETH_REGISTRAR, price);

        bytes32 commitment = IETHRegistrar(ETH_REGISTRAR).makeCommitment(
            LABEL, deployer, SECRET, subregistry, resolver, DURATION, bytes32(0)
        );
        IETHRegistrar(ETH_REGISTRAR).commit(commitment);
        console.log("Committed:", vm.toString(commitment));

        vm.stopBroadcast();
    }

    /// @notice Phase 3: register prove.eth, mint agent1.prove.eth to `agentAddress`, write
    ///         a test text record, and read it back to confirm everything is wired.
    function registerProveAndAgent(address agentAddress) external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);
        (address subregistry, address resolver) = _readInfra();

        vm.startBroadcast(pk);

        IETHRegistrar(ETH_REGISTRAR).register(
            LABEL, deployer, SECRET, subregistry, resolver, DURATION, MOCK_USDC, bytes32(0)
        );
        console.log("Registered prove.eth, owner:", deployer);

        IUserRegistry(subregistry).register(
            "agent1", agentAddress, address(0), resolver, 0, type(uint64).max
        );
        console.log("Registered agent1.prove.eth, owner:", agentAddress);

        bytes32 agent1Node = _agent1Node();
        IPermissionedResolver(resolver).setText(agent1Node, "com.prove.trustScore", "0");

        vm.stopBroadcast();

        string memory readBack = IPermissionedResolver(resolver).text(agent1Node, "com.prove.trustScore");
        console.log("agent1.prove.eth com.prove.trustScore =", readBack);
    }

    function _readInfra() internal view returns (address subregistry, address resolver) {
        string memory json = vm.readFile(OUTPUT_PATH);
        subregistry = vm.parseJsonAddress(json, ".subregistry");
        resolver = vm.parseJsonAddress(json, ".resolver");
    }

    /// @dev Standard ENS namehash for "agent1.prove.eth", computed right-to-left.
    function _agent1Node() internal pure returns (bytes32) {
        bytes32 ethNode = keccak256(abi.encodePacked(bytes32(0), keccak256(bytes("eth"))));
        bytes32 proveNode = keccak256(abi.encodePacked(ethNode, keccak256(bytes("prove"))));
        return keccak256(abi.encodePacked(proveNode, keccak256(bytes("agent1"))));
    }
}
