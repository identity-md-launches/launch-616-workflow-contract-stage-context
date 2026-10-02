# Implementation review handoff

This is the builder's review handoff, not an independent audit or launch approval. The separate reviewer should examine accepted source and the generated manifest together. The canonical protected tests supplied for the assignment are a deployment/token baseline; they do not establish arbitrary registry correctness. Local tests include a factory-style CREATE2 fixture and a runtime scan with the same opcode exclusions, without using environment variables or requiring service artifacts.

## Design observations

- Registry authorization comes exclusively from `entryIdOf[msg.sender]`; mutation APIs have no target-entry argument. The factory obtains no registry privileges at construction. The organizer constant only excludes an entrant and grants no authority.
- All entry changes emit events. IDs and their address mappings are permanent. Unregistration cannot recycle an ID, erase history or permit a second entry.
- Register/update reject timestamp equality with the deadline. Withdrawal remains open and irrevocable. Block timestamps are intentionally the clock requested by the brief, not a source of randomness. Deadline-related validator/inclusion timing must be reflected in the frontend; Foundry's timestamp lint warning corresponds to this intentional comparison.
- Field byte lengths and toolkit mask bounds apply identically to register and update. These are metadata constraints, not URL validation, identity verification or proof of actual toolkit use.
- There are no application external calls or callbacks, so registry actions cannot be reentered through an interaction. A contract entrant test has a reverting fallback and completes the entire lifecycle. There is no payment, randomness, oracle, signed authorization, delegatecall, selfdestruct or upgrade facility to exercise.
- The ordinary OpenZeppelin v5.1.0 ERC-20 implementation is vendored. `LaunchToken` adds only its zero-argument constructor and initial mint. Internal mint/burn helpers in the dependency have no post-construction public reachability in the delivered token.
- A registry read returns one bounded entry; state-changing work is bounded independently of entrant count. Full enumeration belongs to client batching. There is no storage-clearing loop or global settlement transaction that participants could make exceed block gas limits.
- The token and registry are independent. Registry deployment and use cannot move or mutate token supply. The factory's token balance remains exactly `10^27` minor units across application construction in the local fixture.

## Assumptions and operational responsibilities

| Responsible party | Required work |
| --- | --- |
| Manifest contributor | Describe these accepted source contracts, token metadata and zero constructor arguments; list only `HackathonRegistry` as application; apply canonical pool parameters; write `launch.json` |
| Independent reviewer | Review source and manifest, including the constant organizer exclusion, constructor semantics, exact deadline, withdrawal interpretation, fixed supply and concrete policy/authorization compatibility |
| Launch services | Resolve policy and signed-artifact linkage, publish and attest source, admit and deploy on Sepolia, verify explorer code, deliver addresses/deployment block/deadline/ABIs/poolKey |
| Website contributor | Use the live registry; publish the unofficial notice and banner on every page, the exact prize split and rubric, steps/eligibility/FAQ and toolkit links/status; validate links and render untrusted strings safely |
| Judging service | Preserve a finalized deadline snapshot and reviewed repo/demo versions; check public access and toolkit claims; exclude withdrawn/organizer entries; obtain 4-of-7 agreement or use one fallback swarm judge; publish results |
| Organizer prize service | Verify organizer inventory and mainnet recipient control expectations; check withdrawals before executing; pay the same entrant address on mainnet after successful judging; prevent duplicate payments and publish receipts |

Only the one organizer wallet provided by the brief can be excluded directly. Additional organizer-controlled wallets must be handled in eligibility review. The registry cannot enforce one human per wallet or require that a Sepolia smart-contract address is controlled on mainnet. The published EOA guidance is consequently material.

Prizes remain entirely with the organizer. There is no registry payout guarantee, cross-chain bridge, signing key, funded wallet, automated judging worker or custody of the NFT/IMD in this contribution. Failure of judging means no guaranteed payout; zero eligible entries means no payout. Unawarded places retain their shares with the organizer under the documented prize rule.

## Local validation

The required commands are `forge build`, `forge test` and `forge fmt --check`, using the repository's pinned Solidity 0.8.26 compiler. ABI verification is `python3 scripts/export_abi.py --check`. Fuzzing uses 256 cases per fuzz test; stateful invariants use 128 runs of depth 64, with unexpected reverts treated as failures. Tests have fresh setup state and do not read or write environment variables, use RPC forks, enable FFI or request filesystem permissions. Vendored dependency hashes are recorded in `dependencies.json`.

The completed local run passed all four commands: 44 Foundry tests passed, zero failed and zero skipped. The invariant campaign completed 8,192 calls with zero unexpected reverts. Both zero-argument constructors and ABI exports were checked. Runtime sizes were 1,709 bytes for `LaunchToken` and 3,567 bytes for `HackathonRegistry`, below the 24,576-byte limit; the opcode scan passed. All 36 vendored dependency files matched their recorded SHA-256 hashes. These are builder observations, not independent approval.

No independent review, Slither, Mythril, live-chain deployment, source publication or prize-wallet verification is claimed by these local checks. Those outcomes are not prerequisites for this source contribution.
