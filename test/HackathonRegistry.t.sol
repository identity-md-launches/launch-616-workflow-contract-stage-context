// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {HackathonRegistry} from "../src/HackathonRegistry.sol";

contract HackathonRegistryTest is Test {
    HackathonRegistry private registry;
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    string private constant REPO = "https://example.org/swarm/project";
    string private constant DEMO = "https://example.org/demo";

    function setUp() public {
        vm.warp(1_800_000_000);
        registry = new HackathonRegistry();
    }

    function testConstructorSetsExactDeadlineAndEmitsEvent() public {
        vm.warp(1_900_000_000);
        vm.expectEmit();
        emit HackathonRegistry.RegistryOpened(1_900_000_000 + 14 days);
        HackathonRegistry fresh = new HackathonRegistry();
        assertEq(fresh.deadline(), 1_900_000_000 + 14 days);
        assertEq(fresh.entryCount(), 0);
        assertEq(fresh.entryIdOf(ALICE), 0);
        assertEq(fresh.VALID_TOOLKIT_MASK(), 524_287);
    }

    function testRegistrationStoresAllFieldsAndEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(registry));
        emit HackathonRegistry.EntryRegistered(1, ALICE, "Spark", REPO, DEMO, 5);
        uint256 id = _register(ALICE);
        assertEq(id, 1);
        assertEq(registry.entryIdOf(ALICE), id);
        assertEq(registry.entryCount(), 1);
        HackathonRegistry.Entry memory entry = registry.getEntry(id);
        assertEq(entry.entrant, ALICE);
        assertEq(entry.projectName, "Spark");
        assertEq(entry.repositoryUrl, REPO);
        assertEq(entry.demoUrl, DEMO);
        assertEq(entry.toolkitMask, 5);
        assertFalse(entry.withdrawn);
    }

    function testStableEnumerationIncludesWithdrawnEntries() public {
        _register(ALICE);
        _register(BOB);
        vm.prank(ALICE);
        registry.withdraw();
        assertEq(_register(address(0xCAFE)), 3);
        assertEq(registry.entryCount(), 3);
        assertEq(registry.getEntry(1).entrant, ALICE);
        assertTrue(registry.getEntry(1).withdrawn);
        assertEq(registry.getEntry(2).entrant, BOB);
        assertEq(registry.getEntry(3).entrant, address(0xCAFE));
    }

    function testUpdateReplacesOnlyCallersMetadataAndEmitsEvent() public {
        _register(ALICE);
        _register(BOB);
        bytes32 bobBefore = keccak256(abi.encode(registry.getEntry(2)));
        vm.expectEmit(true, true, false, true, address(registry));
        emit HackathonRegistry.EntryUpdated(1, ALICE, "Updated", DEMO, REPO, 1 << 18);
        vm.prank(ALICE);
        registry.update("Updated", DEMO, REPO, 1 << 18);
        HackathonRegistry.Entry memory entry = registry.getEntry(1);
        assertEq(entry.entrant, ALICE);
        assertEq(entry.projectName, "Updated");
        assertEq(entry.repositoryUrl, DEMO);
        assertEq(entry.demoUrl, REPO);
        assertEq(entry.toolkitMask, 1 << 18);
        assertFalse(entry.withdrawn);
        assertEq(registry.entryCount(), 2);
        assertEq(registry.entryIdOf(ALICE), 1);
        assertEq(keccak256(abi.encode(registry.getEntry(2))), bobBefore);
    }

    function testUnregisteredCallerCannotUpdateOrWithdrawExistingEntry() public {
        _register(ALICE);
        bytes32 beforeEntry = keccak256(abi.encode(registry.getEntry(1)));
        vm.startPrank(BOB);
        vm.expectRevert(HackathonRegistry.NotRegistered.selector);
        registry.update("Stolen", REPO, DEMO, 1);
        vm.expectRevert(HackathonRegistry.NotRegistered.selector);
        registry.withdraw();
        vm.stopPrank();
        assertEq(keccak256(abi.encode(registry.getEntry(1))), beforeEntry);
    }

    function testEntrantCannotWithdrawAnotherEntry() public {
        _register(ALICE);
        _register(BOB);
        vm.prank(BOB);
        registry.withdraw();
        assertFalse(registry.getEntry(1).withdrawn);
        assertTrue(registry.getEntry(2).withdrawn);
    }

    function testDuplicateRegistrationRevertsWithoutChangingState() public {
        _register(ALICE);
        vm.expectRevert(HackathonRegistry.AlreadyRegistered.selector);
        _register(ALICE);
        assertEq(registry.entryCount(), 1);
        assertEq(registry.entryIdOf(ALICE), 1);
    }

    function testOrganiserCannotEnter() public {
        address organiser = registry.ORGANISER();
        vm.expectRevert(HackathonRegistry.OrganiserIneligible.selector);
        _register(organiser);
        assertEq(registry.entryCount(), 0);
        assertEq(registry.entryIdOf(organiser), 0);
    }

    function testWithdrawalEmitsEventAndPreservesMetadata() public {
        _register(ALICE);
        HackathonRegistry.Entry memory expected = registry.getEntry(1);
        expected.withdrawn = true;
        vm.expectEmit(true, true, false, true, address(registry));
        emit HackathonRegistry.EntryWithdrawn(1, ALICE);
        vm.prank(ALICE);
        registry.withdraw();
        assertEq(abi.encode(registry.getEntry(1)), abi.encode(expected));
        assertEq(registry.entryIdOf(ALICE), 1);
        assertEq(registry.entryCount(), 1);
    }

    function testWithdrawalIsPermanent() public {
        _register(ALICE);
        vm.startPrank(ALICE);
        registry.withdraw();
        vm.expectRevert(HackathonRegistry.EntryAlreadyWithdrawn.selector);
        registry.withdraw();
        vm.expectRevert(HackathonRegistry.EntryAlreadyWithdrawn.selector);
        registry.update("Return", REPO, DEMO, 1);
        vm.expectRevert(HackathonRegistry.AlreadyRegistered.selector);
        registry.register("Return", REPO, DEMO, 1);
        vm.stopPrank();
    }

    function testRegistrationAndUpdatesSucceedOneSecondBeforeDeadline() public {
        vm.warp(registry.deadline() - 1);
        _register(ALICE);
        vm.prank(ALICE);
        registry.update("Last second", REPO, DEMO, 2);
        assertEq(registry.getEntry(1).projectName, "Last second");
    }

    function testRegistrationAndUpdatesFailExactlyAtDeadline() public {
        _register(ALICE);
        uint256 deadline = registry.deadline();
        vm.warp(deadline);
        _assertClosed();
        assertEq(registry.deadline(), deadline);
        assertEq(registry.getEntry(1).projectName, "Spark");
        assertEq(registry.entryCount(), 1);
    }

    function testFuzzRegistrationAndUpdatesFailAfterDeadline(uint32 secondsLate) public {
        _register(ALICE);
        vm.warp(registry.deadline() + uint256(secondsLate) + 1);
        _assertClosed();
    }

    function testWithdrawalAllowedAtAndAfterDeadline() public {
        _register(ALICE);
        _register(BOB);
        vm.warp(registry.deadline());
        vm.prank(ALICE);
        registry.withdraw();
        vm.warp(registry.deadline() + 30 days);
        vm.prank(BOB);
        registry.withdraw();
        assertTrue(registry.getEntry(1).withdrawn);
        assertTrue(registry.getEntry(2).withdrawn);
    }

    function testInvalidIdsRevert() public {
        vm.expectRevert(HackathonRegistry.InvalidEntryId.selector);
        registry.getEntry(0);
        vm.expectRevert(HackathonRegistry.InvalidEntryId.selector);
        registry.getEntry(1);
        _register(ALICE);
        vm.expectRevert(HackathonRegistry.InvalidEntryId.selector);
        registry.getEntry(2);
        vm.expectRevert(HackathonRegistry.InvalidEntryId.selector);
        registry.getEntry(type(uint256).max);
    }

    function testEveryToolkitBitIsAccepted() public {
        _register(ALICE);
        for (uint256 bit; bit < 19; ++bit) {
            vm.prank(ALICE);
            registry.update("Spark", REPO, DEMO, 1 << bit);
            assertEq(registry.getEntry(1).toolkitMask, 1 << bit);
        }
    }

    function testMaximumLengthsAndAllToolkitBitsAccepted() public {
        string memory name = _filled(64);
        string memory url = _filled(200);
        vm.prank(ALICE);
        registry.register(name, url, url, 524_287);
        HackathonRegistry.Entry memory entry = registry.getEntry(1);
        assertEq(bytes(entry.projectName).length, 64);
        assertEq(bytes(entry.repositoryUrl).length, 200);
        assertEq(bytes(entry.demoUrl).length, 200);
        assertEq(entry.toolkitMask, 524_287);
    }

    function testEmptyAndOversizeNamesRejectedOnRegisterAndUpdate() public {
        _rejectBoth("", REPO, DEMO, 1, HackathonRegistry.InvalidNameLength.selector);
        _rejectBoth(_filled(65), REPO, DEMO, 1, HackathonRegistry.InvalidNameLength.selector);
    }

    function testEmptyAndOversizeRepositoryUrlsRejectedOnRegisterAndUpdate() public {
        _rejectBoth("Spark", "", DEMO, 1, HackathonRegistry.InvalidRepositoryUrlLength.selector);
        _rejectBoth("Spark", _filled(201), DEMO, 1, HackathonRegistry.InvalidRepositoryUrlLength.selector);
    }

    function testEmptyAndOversizeDemoUrlsRejectedOnRegisterAndUpdate() public {
        _rejectBoth("Spark", REPO, "", 1, HackathonRegistry.InvalidDemoUrlLength.selector);
        _rejectBoth("Spark", REPO, _filled(201), 1, HackathonRegistry.InvalidDemoUrlLength.selector);
    }

    function testZeroToolkitMaskRejectedOnRegisterAndUpdate() public {
        _rejectBoth("Spark", REPO, DEMO, 0, HackathonRegistry.InvalidToolkitMask.selector);
    }

    function testFuzzUnknownToolkitBitsRejectedOnRegisterAndUpdate(uint256 seed) public {
        uint256 invalidMask = bound(seed, 524_288, type(uint256).max);
        _rejectBoth("Spark", REPO, DEMO, invalidMask, HackathonRegistry.InvalidToolkitMask.selector);
    }

    function testLengthsAreBytesNotCharacters() public {
        string memory atLimit;
        for (uint256 i; i < 32; ++i) {
            atLimit = string.concat(atLimit, unicode"é");
        }
        vm.prank(ALICE);
        registry.register(atLimit, REPO, DEMO, 1);
        assertEq(bytes(registry.getEntry(1).projectName).length, 64);
        vm.expectRevert(HackathonRegistry.InvalidNameLength.selector);
        vm.prank(ALICE);
        registry.update(string.concat(atLimit, "a"), REPO, DEMO, 1);
    }

    function testFuzzValidMetadataRoundTrips(uint8 n, uint8 r, uint8 d, uint256 mask) public {
        string memory name = _filled(bound(n, 1, 64));
        string memory repo = _filled(bound(r, 1, 200));
        string memory demo = _filled(bound(d, 1, 200));
        mask = bound(mask, 1, 524_287);
        vm.prank(ALICE);
        registry.register(name, repo, demo, mask);
        HackathonRegistry.Entry memory entry = registry.getEntry(1);
        assertEq(entry.projectName, name);
        assertEq(entry.repositoryUrl, repo);
        assertEq(entry.demoUrl, demo);
        assertEq(entry.toolkitMask, mask);
    }

    function testNoEthDepositsAndPayableRegistrationFailsAtomically() public {
        vm.deal(ALICE, 1 ether);
        vm.startPrank(ALICE);
        (bool received,) = address(registry).call{value: 1}("");
        assertFalse(received);
        (bool registered,) =
            address(registry).call{value: 1}(abi.encodeCall(registry.register, ("Spark", REPO, DEMO, 1)));
        assertFalse(registered);
        vm.stopPrank();
        assertEq(registry.entryCount(), 0);
        assertEq(registry.entryIdOf(ALICE), 0);
        assertEq(address(registry).balance, 0);
    }

    function testContractWalletMayEnterWithoutReceivingCallbacks() public {
        RegistryEntrant entrant = new RegistryEntrant(registry);
        entrant.enter();
        assertEq(registry.getEntry(1).entrant, address(entrant));
        entrant.edit();
        assertEq(registry.getEntry(1).projectName, "Contract update");
        entrant.leave();
        assertTrue(registry.getEntry(1).withdrawn);
    }

    function testDeployerCannotChangeDeadlineOrEditAnotherEntry() public {
        _register(ALICE);
        uint256 deadline = registry.deadline();
        (bool changed,) = address(registry).call(abi.encodeWithSignature("setDeadline(uint256)", type(uint256).max));
        assertFalse(changed);
        vm.expectRevert(HackathonRegistry.NotRegistered.selector);
        registry.update("Admin edit", REPO, DEMO, 1);
        assertEq(registry.deadline(), deadline);
        assertEq(registry.getEntry(1).projectName, "Spark");
    }

    function _assertClosed() private {
        vm.expectRevert(HackathonRegistry.RegistrationClosed.selector);
        _register(BOB);
        vm.expectRevert(HackathonRegistry.RegistrationClosed.selector);
        vm.prank(ALICE);
        registry.update("Late", REPO, DEMO, 1);
    }

    function _register(address entrant) private returns (uint256) {
        vm.prank(entrant);
        return registry.register("Spark", REPO, DEMO, 5);
    }

    function _rejectBoth(string memory name, string memory repo, string memory demo, uint256 mask, bytes4 error)
        private
    {
        uint256 count = registry.entryCount();
        vm.expectRevert(error);
        vm.prank(BOB);
        registry.register(name, repo, demo, mask);
        assertEq(registry.entryCount(), count);
        assertEq(registry.entryIdOf(BOB), 0);
        if (registry.entryIdOf(ALICE) == 0) _register(ALICE);
        bytes32 beforeEntry = keccak256(abi.encode(registry.getEntry(1)));
        vm.expectRevert(error);
        vm.prank(ALICE);
        registry.update(name, repo, demo, mask);
        assertEq(keccak256(abi.encode(registry.getEntry(1))), beforeEntry);
    }

    function _filled(uint256 size) private pure returns (string memory) {
        bytes memory data = new bytes(size);
        for (uint256 i; i < size; ++i) {
            data[i] = "a";
        }
        return string(data);
    }
}

contract RegistryEntrant {
    HackathonRegistry private immutable registry;

    constructor(HackathonRegistry registry_) {
        registry = registry_;
    }

    function enter() external {
        registry.register("Contract", "https://example.org/repo", "https://example.org/demo", 1);
    }

    function edit() external {
        registry.update("Contract update", "https://example.org/repo", "https://example.org/demo", 2);
    }

    function leave() external {
        registry.withdraw();
    }

    fallback() external {
        revert("registry must not call the entrant");
    }
}
