// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Fixed-supply launch token. HACK has no role in hackathon entry, judging or prizes.
contract LaunchToken is ERC20 {
    /// @dev The launch factory receives the full supply and performs the protocol allocation.
    constructor() ERC20("Swarm Hackathon Token", "HACK") {
        _mint(msg.sender, 1_000_000_000 * 10 ** 18);
    }
}
