// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {HackathonRegistry} from "../src/HackathonRegistry.sol";

/// @dev Independent per-actor history model checked after randomized lifecycle sequences.
contract RegistryHandler is Test {
    HackathonRegistry public immutable registry;
    uint256 public immutable closesAt;
    uint256 public clock;
    uint256 public registrations;
    mapping(address => uint256) public expectedId;
    mapping(address => bytes32) public expectedMetadata;
    mapping(address => bool) public expectedWithdrawn;

    constructor(HackathonRegistry registry_) {
        registry = registry_;
        clock = block.timestamp;
        closesAt = registry_.deadline();
    }

    function actor(uint256 seed) public pure returns (address) {
        return address(uint160(0x1000 + seed % 6));
    }

    function register(uint256 seed, uint256 maskSeed) external {
        address entrant = actor(seed);
        // Exercise invalid transitions instead of silently discarding them.
        if (clock >= closesAt || expectedId[entrant] != 0) {
            vm.expectRevert(
                clock >= closesAt
                    ? HackathonRegistry.RegistrationClosed.selector
                    : HackathonRegistry.AlreadyRegistered.selector
            );
            vm.prank(entrant);
            registry.register("Initial", "https://repo.example/initial", "https://demo.example/initial", 1);
            return;
        }
        uint256 mask = 1 + maskSeed % 524_287;
        vm.prank(entrant);
        uint256 actualId =
            registry.register("Initial", "https://repo.example/initial", "https://demo.example/initial", mask);
        expectedId[entrant] = ++registrations;
        expectedMetadata[entrant] =
            keccak256(abi.encode("Initial", "https://repo.example/initial", "https://demo.example/initial", mask));
        assertEq(actualId, registrations);
    }

    function update(uint256 seed, uint256 maskSeed) external {
        address entrant = actor(seed);
        if (clock >= closesAt || expectedId[entrant] == 0 || expectedWithdrawn[entrant]) {
            bytes4 reason = clock >= closesAt
                ? HackathonRegistry.RegistrationClosed.selector
                : expectedId[entrant] == 0
                    ? HackathonRegistry.NotRegistered.selector
                    : HackathonRegistry.EntryAlreadyWithdrawn.selector;
            vm.expectRevert(reason);
            vm.prank(entrant);
            registry.update("Rejected edit", "https://repo.example/rejected", "https://demo.example/rejected", 1);
            return;
        }
        uint256 mask = 1 + maskSeed % 524_287;
        vm.prank(entrant);
        registry.update("Edited", "https://repo.example/edited", "https://demo.example/edited", mask);
        expectedMetadata[entrant] =
            keccak256(abi.encode("Edited", "https://repo.example/edited", "https://demo.example/edited", mask));
    }

    function withdraw(uint256 seed) external {
        address entrant = actor(seed);
        if (expectedId[entrant] == 0 || expectedWithdrawn[entrant]) {
            vm.expectRevert(
                expectedId[entrant] == 0
                    ? HackathonRegistry.NotRegistered.selector
                    : HackathonRegistry.EntryAlreadyWithdrawn.selector
            );
            vm.prank(entrant);
            registry.withdraw();
            return;
        }
        vm.prank(entrant);
        registry.withdraw();
        expectedWithdrawn[entrant] = true;
    }

    function organiserRegister() external {
        address organiser = registry.ORGANISER();
        vm.expectRevert(
            clock >= closesAt
                ? HackathonRegistry.RegistrationClosed.selector
                : HackathonRegistry.OrganiserIneligible.selector
        );
        vm.prank(organiser);
        registry.register("Organiser", "https://repo.example", "https://demo.example", 1);
        assertEq(registry.entryIdOf(organiser), 0);
    }

    function elapse(uint256 seed) external {
        clock += seed % (2 days + 1);
        vm.warp(clock);
    }
}

contract RegistryInvariantTest is StdInvariant, Test {
    HackathonRegistry private registry;
    RegistryHandler private handler;
    uint256 private initialDeadline;

    function setUp() public {
        vm.warp(1_800_000_000);
        registry = new HackathonRegistry();
        initialDeadline = registry.deadline();
        handler = new RegistryHandler(registry);
        // Every sequence starts with live entries, even if time advances immediately.
        handler.register(0, 0);
        handler.register(1, 18);
        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = RegistryHandler.register.selector;
        selectors[1] = RegistryHandler.update.selector;
        selectors[2] = RegistryHandler.withdraw.selector;
        selectors[3] = RegistryHandler.elapse.selector;
        selectors[4] = RegistryHandler.organiserRegister.selector;
        targetSelector(FuzzSelector(address(handler), selectors));
        targetContract(address(handler));
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariantOnePermanentIdAndOnlySelfChanges() public view {
        assertEq(registry.entryCount(), handler.registrations());
        assertLe(registry.entryCount(), 6);
        for (uint256 i; i < 6; ++i) {
            address entrant = handler.actor(i);
            uint256 expectedId = handler.expectedId(entrant);
            assertEq(registry.entryIdOf(entrant), expectedId);
            if (expectedId == 0) continue;
            HackathonRegistry.Entry memory entry = registry.getEntry(expectedId);
            assertEq(entry.entrant, entrant);
            assertEq(entry.withdrawn, handler.expectedWithdrawn(entrant));
            assertEq(
                keccak256(abi.encode(entry.projectName, entry.repositoryUrl, entry.demoUrl, entry.toolkitMask)),
                handler.expectedMetadata(entrant)
            );
        }
        for (uint256 id = 1; id <= registry.entryCount(); ++id) {
            assertEq(registry.entryIdOf(registry.getEntry(id).entrant), id);
        }
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariantDeadlineAndNoCustody() public view {
        assertEq(registry.deadline(), initialDeadline);
        assertEq(address(registry).balance, 0);
    }
}
