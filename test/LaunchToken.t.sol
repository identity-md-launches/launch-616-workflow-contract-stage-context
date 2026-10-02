// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {LaunchToken} from "../src/LaunchToken.sol";

contract LaunchTokenTest is Test {
    LaunchToken private token;
    uint256 private constant SUPPLY = 1e27;
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);

    function setUp() public {
        token = new LaunchToken();
    }

    function testMetadataAndExactSupplyMintedOnlyToDeployer() public view {
        assertEq(token.name(), "Swarm Hackathon Token");
        assertEq(token.symbol(), "HACK");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function testConstructorEmitsMintTransferToActualDeployer() public {
        vm.expectEmit(true, true, false, true);
        emit IERC20.Transfer(address(0), ALICE, SUPPLY);
        vm.prank(ALICE);
        LaunchToken other = new LaunchToken();
        assertEq(other.balanceOf(ALICE), SUPPLY);
        assertEq(other.balanceOf(address(this)), 0);
    }

    function testTransferMovesExactAmountAndEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(address(this), ALICE, 10 ether);
        assertTrue(token.transfer(ALICE, 10 ether));
        assertEq(token.balanceOf(ALICE), 10 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 10 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testApproveAndTransferFromSpendAllowance() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Approval(address(this), ALICE, 7 ether);
        assertTrue(token.approve(ALICE, 7 ether));
        vm.prank(ALICE);
        assertTrue(token.transferFrom(address(this), BOB, 3 ether));
        assertEq(token.allowance(address(this), ALICE), 4 ether);
        assertEq(token.balanceOf(BOB), 3 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 3 ether);
    }

    function testApproveOverwriteAndRevoke() public {
        token.approve(ALICE, 9 ether);
        token.approve(ALICE, 2 ether);
        assertEq(token.allowance(address(this), ALICE), 2 ether);
        token.approve(ALICE, 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, ALICE, 0, 1));
        vm.prank(ALICE);
        token.transferFrom(address(this), BOB, 1);
    }

    function testInfiniteAllowanceIsNotReduced() public {
        token.approve(ALICE, type(uint256).max);
        vm.prank(ALICE);
        token.transferFrom(address(this), BOB, 100 ether);
        assertEq(token.allowance(address(this), ALICE), type(uint256).max);
    }

    function testInsufficientBalanceReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, 1));
        vm.prank(ALICE);
        token.transfer(BOB, 1);
        assertEq(token.balanceOf(BOB), 0);
    }

    function testInsufficientAllowanceRevertsWithoutMovingTokens() public {
        token.approve(ALICE, 4);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, ALICE, 4, 5));
        vm.prank(ALICE);
        token.transferFrom(address(this), BOB, 5);
        assertEq(token.allowance(address(this), ALICE), 4);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(BOB), 0);
    }

    function testRevertedTransferFromRestoresAllowance() public {
        vm.prank(ALICE);
        token.approve(address(this), 10);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, 10));
        token.transferFrom(ALICE, BOB, 10);
        assertEq(token.allowance(ALICE, address(this)), 10);
    }

    function testZeroReceiverAndSpenderRevert() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
        token.approve(ALICE, 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(ALICE);
        token.transferFrom(address(this), address(0), 1);
        assertEq(token.allowance(address(this), ALICE), 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testZeroTransferAndSelfTransferPreserveSupply() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(ALICE, BOB, 0);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 0));
        token.transfer(address(this), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzzTransfersConserveSupply(uint256 first, uint256 second) public {
        first = bound(first, 0, SUPPLY);
        second = bound(second, 0, first);
        token.transfer(ALICE, first);
        vm.prank(ALICE);
        token.transfer(BOB, second);
        assertEq(token.balanceOf(address(this)), SUPPLY - first);
        assertEq(token.balanceOf(ALICE), first - second);
        assertEq(token.balanceOf(BOB), second);
        assertEq(token.balanceOf(address(this)) + token.balanceOf(ALICE) + token.balanceOf(BOB), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testNoMintOrAdministrativeSelectorsEvenForDeployer() public {
        string[10] memory signatures = [
            "mint(address,uint256)",
            "mint(uint256)",
            "mint()",
            "burn(uint256)",
            "setOwner(address)",
            "transferOwnership(address)",
            "upgradeTo(address)",
            "initialize(address)",
            "pause()",
            "setMinter(address)"
        ];
        for (uint256 i; i < signatures.length; ++i) {
            bytes memory data = abi.encodeWithSignature(signatures[i], ALICE, 1);
            (bool deployerOk,) = address(token).call(data);
            assertFalse(deployerOk);
            vm.prank(ALICE);
            (bool attackerOk,) = address(token).call(data);
            assertFalse(attackerOk);
        }
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }
}
