// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {HackathonRegistry} from "src/HackathonRegistry.sol";

contract RegistryPropertiesTest is Test {
    HackathonRegistry private registry;
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);

    function setUp() public {
        vm.warp(1_800_000_000);
        registry = new HackathonRegistry();
        vm.prank(ALICE);
        registry.register("Initial", "https://repo.example/initial", "https://demo.example/initial", 1);
        vm.prank(BOB);
        registry.register("Neighbour", "https://repo.example/neighbour", "https://demo.example/neighbour", 2);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzzReplaceAndRestoreAllMetadata(
        uint256 nameSize,
        uint256 repoSize,
        uint256 demoSize,
        bytes32 seed,
        uint256 mask
    ) public {
        _replaceAndRestore(
            _bytes(bound(nameSize, 1, 64), seed),
            _bytes(bound(repoSize, 1, 200), keccak256(abi.encode(seed, uint256(1)))),
            _bytes(bound(demoSize, 1, 200), keccak256(abi.encode(seed, uint256(2)))),
            bound(mask, 1, 524_287)
        );
    }

    function testMetadataCrossesShortAndLongStorageBoundaries() public {
        uint256[7] memory sizes = [uint256(1), 31, 32, 33, 64, 199, 200];
        for (uint256 i; i < sizes.length; ++i) {
            uint256 nameSize = sizes[i] > 64 ? 64 : sizes[i];
            _replaceAndRestore(
                _bytes(nameSize, bytes32("name")),
                _bytes(sizes[i], bytes32("repo")),
                _bytes(200, bytes32("demo")),
                524_287
            );
        }
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzzOversizeFieldRevertsWithoutConsumingAnIdOrChangingEntries(
        uint8 field,
        uint256 excess,
        bytes32 seed
    ) public {
        field = uint8(bound(field, 0, 2));
        // Above each specified byte limit, with bounded allocation to keep the test useful.
        string memory oversized = _bytes((field == 0 ? 64 : 200) + bound(excess, 1, 256), seed);
        string memory name = field == 0 ? oversized : "Valid";
        string memory repo = field == 1 ? oversized : "https://repo.example";
        string memory demo = field == 2 ? oversized : "https://demo.example";
        bytes4 reason = field == 0
            ? HackathonRegistry.InvalidNameLength.selector
            : field == 1
                ? HackathonRegistry.InvalidRepositoryUrlLength.selector
                : HackathonRegistry.InvalidDemoUrlLength.selector;
        bytes32 aliceBefore = keccak256(abi.encode(registry.getEntry(1)));
        bytes32 bobBefore = keccak256(abi.encode(registry.getEntry(2)));

        vm.expectRevert(reason);
        registry.register(name, repo, demo, 1);
        assertEq(registry.entryIdOf(address(this)), 0);
        assertEq(registry.entryCount(), 2);
        vm.expectRevert(reason);
        vm.prank(ALICE);
        registry.update(name, repo, demo, 1);
        assertEq(keccak256(abi.encode(registry.getEntry(1))), aliceBefore);
        assertEq(keccak256(abi.encode(registry.getEntry(2))), bobBefore);
        // Failure must leave this previously unregistered address free to try valid data.
        assertEq(registry.register("Valid", "https://repo.example", "https://demo.example", 1), 3);
        assertEq(registry.entryIdOf(address(this)), 3);
        assertEq(registry.entryCount(), 3);
    }

    function testPaidUpdateAndWithdrawalRejectWithoutMutatingEntry() public {
        bytes32 beforeEntry = keccak256(abi.encode(registry.getEntry(1)));
        vm.deal(ALICE, 2);
        vm.startPrank(ALICE);
        (bool updated,) = address(registry).call{value: 1}(
            abi.encodeCall(registry.update, ("Paid edit", "https://repo.example", "https://demo.example", 1))
        );
        (bool withdrawn,) = address(registry).call{value: 1}(abi.encodeCall(registry.withdraw, ()));
        vm.stopPrank();
        assertFalse(updated);
        assertFalse(withdrawn);
        assertEq(keccak256(abi.encode(registry.getEntry(1))), beforeEntry);
        assertEq(registry.entryCount(), 2);
        assertEq(registry.entryIdOf(ALICE), 1);
        assertEq(ALICE.balance, 2);
        assertEq(address(registry).balance, 0);
    }

    function testTransactionOriginCannotAuthorizeAForwarderToEditOrWithdraw() public {
        RegistryCaller caller = new RegistryCaller();
        bytes32 beforeEntry = keccak256(abi.encode(registry.getEntry(1)));
        // ALICE owns entry 1 but an unregistered intermediate contract is msg.sender.
        vm.prank(ALICE, ALICE);
        vm.expectRevert(HackathonRegistry.NotRegistered.selector);
        caller.edit(registry);
        vm.prank(ALICE, ALICE);
        vm.expectRevert(HackathonRegistry.NotRegistered.selector);
        caller.withdraw(registry);
        assertEq(keccak256(abi.encode(registry.getEntry(1))), beforeEntry);
        assertEq(registry.entryIdOf(address(caller)), 0);
    }

    function _replaceAndRestore(string memory name, string memory repo, string memory demo, uint256 mask) private {
        HackathonRegistry.Entry memory original = registry.getEntry(1);
        bytes32 neighbour = keccak256(abi.encode(registry.getEntry(2)));
        uint256 deadline = registry.deadline();
        vm.expectEmit(true, true, false, true, address(registry));
        emit HackathonRegistry.EntryUpdated(1, ALICE, name, repo, demo, mask);
        vm.prank(ALICE);
        registry.update(name, repo, demo, mask);
        HackathonRegistry.Entry memory expected = HackathonRegistry.Entry(ALICE, name, repo, demo, mask, false);
        assertEq(abi.encode(registry.getEntry(1)), abi.encode(expected));

        // Repeating an update is idempotent, including strings containing zero bytes.
        vm.prank(ALICE);
        registry.update(name, repo, demo, mask);
        assertEq(abi.encode(registry.getEntry(1)), abi.encode(expected));
        vm.prank(ALICE);
        registry.update(original.projectName, original.repositoryUrl, original.demoUrl, original.toolkitMask);
        assertEq(abi.encode(registry.getEntry(1)), abi.encode(original));
        assertEq(keccak256(abi.encode(registry.getEntry(2))), neighbour);
        assertEq(registry.entryCount(), 2);
        assertEq(registry.entryIdOf(ALICE), 1);
        assertEq(registry.entryIdOf(BOB), 2);
        assertEq(registry.deadline(), deadline);
    }

    function _bytes(uint256 length, bytes32 seed) private pure returns (string memory) {
        bytes memory result = new bytes(length);
        for (uint256 i; i < length; ++i) {
            result[i] = seed[i % 32];
        }
        return string(result);
    }
}

contract RegistryCaller {
    function edit(HackathonRegistry registry) external {
        registry.update("Forwarded", "https://repo.example", "https://demo.example", 1);
    }

    function withdraw(HackathonRegistry registry) external {
        registry.withdraw();
    }
}
