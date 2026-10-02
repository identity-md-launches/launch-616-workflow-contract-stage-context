// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {LaunchToken} from "../src/LaunchToken.sol";
import {HackathonRegistry} from "../src/HackathonRegistry.sol";

/// @dev Local execution model only; production ProjectFactory is supplied by launch services.
contract FactoryFixture {
    address private immutable controller = msg.sender;

    function deploy(bytes memory creationCode, bytes32 salt) external returns (address deployed) {
        require(msg.sender == controller, "controller only");
        assembly ("memory-safe") {
            deployed := create2(0, add(creationCode, 32), mload(creationCode), salt)
        }
        require(deployed != address(0), "deployment failed");
    }
}

contract DeploymentTest is Test {
    function testFactoryDeploysCompleteContractsWithoutInitializationOrSupplyMovement() public {
        vm.chainId(11_155_111);
        vm.warp(1_800_000_000);
        FactoryFixture factory = new FactoryFixture();
        LaunchToken token = LaunchToken(factory.deploy(type(LaunchToken).creationCode, bytes32(uint256(1))));
        assertEq(token.balanceOf(address(factory)), 1e27);
        HackathonRegistry registry =
            HackathonRegistry(factory.deploy(type(HackathonRegistry).creationCode, bytes32(uint256(2))));
        assertEq(token.balanceOf(address(factory)), 1e27);
        assertEq(token.balanceOf(address(registry)), 0);
        assertEq(token.totalSupply(), 1e27);
        assertEq(registry.deadline(), 1_800_000_000 + 14 days);
        vm.prank(address(0xA11CE));
        registry.register("Ready", "https://repo.example", "https://demo.example", 1);
        assertEq(registry.entryCount(), 1);
        assertEq(token.balanceOf(address(factory)), 1e27);
    }

    function testRuntimeSizeAndForbiddenOpcodes() public {
        _checkRuntime(address(new LaunchToken()).code);
        _checkRuntime(address(new HackathonRegistry()).code);
    }

    function testConstructorsAreNonpayable() public {
        vm.deal(address(this), 1 ether);
        bytes memory tokenCode = type(LaunchToken).creationCode;
        bytes memory registryCode = type(HackathonRegistry).creationCode;
        address token;
        address registry;
        assembly ("memory-safe") {
            token := create(1, add(tokenCode, 32), mload(tokenCode))
            registry := create(1, add(registryCode, 32), mload(registryCode))
        }
        assertEq(token, address(0));
        assertEq(registry, address(0));
    }

    function _checkRuntime(bytes memory runtime) private pure {
        assertGt(runtime.length, 0);
        assertLe(runtime.length, 24_576);
        for (uint256 i; i < runtime.length; ++i) {
            uint8 op = uint8(runtime[i]);
            if (op >= 0x60 && op <= 0x7f) {
                i += op - 0x5f;
                continue;
            }
            assertTrue(op != 0xf4 && op != 0xf2 && op != 0xff, "forbidden opcode");
        }
    }
}
