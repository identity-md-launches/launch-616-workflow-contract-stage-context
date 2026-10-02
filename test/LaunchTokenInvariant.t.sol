// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {LaunchToken} from "src/LaunchToken.sol";

/// @dev All reachable token holders are in the actor set. Ghosts start from the
/// required constructor allocation and are updated from requests, never token getters.
contract LaunchTokenHandler is Test {
    uint256 public constant SUPPLY = 1e27;
    uint256 public constant ACTORS = 4;
    LaunchToken public immutable token;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor() {
        vm.prank(actor(0));
        token = new LaunchToken();
        expectedBalance[actor(0)] = SUPPLY;
        // Seed funded and empty actors so both success and failure paths are reachable.
        vm.prank(actor(0));
        assertTrue(token.transfer(actor(1), SUPPLY / 4));
        expectedBalance[actor(0)] -= SUPPLY / 4;
        expectedBalance[actor(1)] = SUPPLY / 4;
        _approve(actor(0), actor(1), SUPPLY / 2);
        _approve(actor(1), actor(2), type(uint256).max);
    }

    function actor(uint256 seed) public pure returns (address) {
        return address(uint160(0x10000 + seed % ACTORS));
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = actor(fromSeed);
        address to = actor(toSeed);
        uint256 amount = bound(amountSeed, 0, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        _move(from, to, amount);
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount, uint8 mode) external {
        // Revocation, finite limits, and unlimited approval must all recur in a sequence.
        if (mode % 3 == 0) amount = 0;
        else if (mode % 3 == 1) amount = type(uint256).max;
        _approve(actor(ownerSeed), actor(spenderSeed), amount);
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amountSeed) external {
        address owner = actor(ownerSeed);
        address spender = actor(spenderSeed);
        address to = actor(toSeed);
        uint256 allowance = expectedAllowance[owner][spender];
        uint256 limit = expectedBalance[owner] < allowance ? expectedBalance[owner] : allowance;
        uint256 amount = bound(amountSeed, 0, limit);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        _move(owner, to, amount);
        if (allowance != type(uint256).max) expectedAllowance[owner][spender] -= amount;
    }

    function transferAboveBalance(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = actor(fromSeed);
        uint256 balance = expectedBalance[from];
        uint256 amount = bound(amountSeed, balance + 1, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount));
        vm.prank(from);
        token.transfer(actor(toSeed), amount);
        // No ghost changes: invariants require the entire ledger to remain intact.
    }

    function transferFromAboveAllowance(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 seed) external {
        address owner = actor(ownerSeed);
        address spender = actor(spenderSeed);
        uint256 allowance = bound(seed, 0, type(uint256).max - 1);
        _approve(owner, spender, allowance);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowance, allowance + 1)
        );
        vm.prank(spender);
        token.transferFrom(owner, actor(toSeed), allowance + 1);
    }

    function transferFromAboveBalance(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, bool infinite) external {
        address owner = actor(ownerSeed);
        address spender = actor(spenderSeed);
        uint256 balance = expectedBalance[owner];
        uint256 amount = balance + 1;
        _approve(owner, spender, infinite ? type(uint256).max : amount);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, amount));
        vm.prank(spender);
        token.transferFrom(owner, actor(toSeed), amount);
        // A failed transferFrom must also roll back any attempted allowance debit.
    }

    function zeroAddressCalls(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed) external {
        address owner = actor(ownerSeed);
        address spender = actor(spenderSeed);
        uint256 amount = bound(amountSeed, 0, expectedBalance[owner]);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(owner);
        token.transfer(address(0), amount);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(owner);
        token.approve(address(0), amount);
        _approve(owner, spender, amount);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(owner, address(0), amount);
    }

    function _approve(address owner, address spender, uint256 amount) private {
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function _move(address from, address to, uint256 amount) private {
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }
}

contract LaunchTokenInvariantTest is StdInvariant, Test {
    LaunchToken private token;
    LaunchTokenHandler private handler;

    function setUp() public {
        handler = new LaunchTokenHandler();
        token = handler.token();
        bytes4[] memory selectors = new bytes4[](7);
        selectors[0] = LaunchTokenHandler.transfer.selector;
        selectors[1] = LaunchTokenHandler.approve.selector;
        selectors[2] = LaunchTokenHandler.transferFrom.selector;
        selectors[3] = LaunchTokenHandler.transferAboveBalance.selector;
        selectors[4] = LaunchTokenHandler.transferFromAboveAllowance.selector;
        selectors[5] = LaunchTokenHandler.transferFromAboveBalance.selector;
        selectors[6] = LaunchTokenHandler.zeroAddressCalls.selector;
        targetSelector(FuzzSelector(address(handler), selectors));
        targetContract(address(handler));
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_FixedSupplyAndExactBalancesAndAllowances() public view {
        uint256 sum;
        for (uint256 i; i < 4; ++i) {
            address owner = handler.actor(i);
            uint256 balance = token.balanceOf(owner);
            assertEq(balance, handler.expectedBalance(owner), "unexpected credit or debit");
            sum += balance;
            for (uint256 j; j < 4; ++j) {
                address spender = handler.actor(j);
                assertEq(
                    token.allowance(owner, spender),
                    handler.expectedAllowance(owner, spender),
                    "allowance spent, restored or overwritten incorrectly"
                );
            }
            assertEq(token.allowance(owner, address(0)), 0);
        }
        assertEq(sum, 1e27, "tokens created, destroyed or diverted");
        assertEq(token.totalSupply(), 1e27);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
    }
}
