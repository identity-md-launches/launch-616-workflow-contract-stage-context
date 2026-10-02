// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {LaunchToken} from "src/LaunchToken.sol";

contract LaunchTokenPropertiesTest is Test {
    LaunchToken private token;
    uint256 private constant SUPPLY = 1e27;
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant CAROL = address(0xCA401);

    function setUp() public {
        token = new LaunchToken();
        assertTrue(token.transfer(ALICE, SUPPLY));
    }

    function testWholeSupplyCanMoveWithExactAllowanceThenCannotBeSpentAgain() public {
        vm.prank(ALICE);
        assertTrue(token.approve(BOB, SUPPLY));
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(ALICE, CAROL, SUPPLY);
        vm.prank(BOB);
        assertTrue(token.transferFrom(ALICE, CAROL, SUPPLY));
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(CAROL), SUPPLY);
        assertEq(token.allowance(ALICE, BOB), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, BOB, 0, 1));
        vm.prank(BOB);
        token.transferFrom(ALICE, CAROL, 1);
        // The recipient can return the complete supply without losing a fee or dust.
        vm.prank(CAROL);
        assertTrue(token.transfer(ALICE, SUPPLY));
        assertEq(token.balanceOf(ALICE), SUPPLY);
        assertEq(token.balanceOf(CAROL), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testMaximumTransferFailsAndPreservesFiniteAndInfiniteAllowances() public {
        for (uint256 i; i < 2; ++i) {
            uint256 amount = type(uint256).max - i;
            vm.prank(ALICE);
            token.approve(BOB, amount);
            vm.expectRevert(
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, SUPPLY, amount)
            );
            vm.prank(BOB);
            token.transferFrom(ALICE, CAROL, amount);
            assertEq(token.allowance(ALICE, BOB), amount);
            assertEq(token.balanceOf(ALICE), SUPPLY);
            assertEq(token.balanceOf(CAROL), 0);
        }
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzzSelfTransferFromConsumesOnlyItsFiniteAllowance(uint256 amount) public {
        amount = bound(amount, 0, SUPPLY);
        vm.prank(ALICE);
        token.approve(BOB, amount);
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(ALICE, ALICE, amount);
        vm.prank(BOB);
        assertTrue(token.transferFrom(ALICE, ALICE, amount));
        assertEq(token.balanceOf(ALICE), SUPPLY);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.allowance(ALICE, BOB), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzzApprovalCannotBeUsedByAnotherSpender(uint256 amount) public {
        amount = bound(amount, 1, SUPPLY);
        vm.prank(ALICE);
        token.approve(BOB, amount);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, CAROL, 0, amount));
        vm.prank(CAROL);
        token.transferFrom(ALICE, CAROL, amount);
        assertEq(token.balanceOf(ALICE), SUPPLY);
        assertEq(token.balanceOf(CAROL), 0);
        assertEq(token.allowance(ALICE, BOB), amount);
        // The failed theft must not interfere with the authorised spender's next call.
        vm.prank(BOB);
        assertTrue(token.transferFrom(ALICE, BOB, amount));
        assertEq(token.balanceOf(ALICE), SUPPLY - amount);
        assertEq(token.balanceOf(BOB), amount);
        assertEq(token.allowance(ALICE, BOB), 0);
    }

    function testZeroTransferFromNeedsNoAllowanceButStillRejectsZeroAddresses() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(BOB, CAROL, 0);
        assertTrue(token.transferFrom(BOB, CAROL, 0));
        // transferFrom validates the allowance owner before reaching the transfer.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        token.transferFrom(address(0), CAROL, 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transferFrom(BOB, address(0), 0);
        assertEq(token.balanceOf(ALICE), SUPPLY);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.balanceOf(CAROL), 0);
        assertEq(token.allowance(BOB, address(this)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
