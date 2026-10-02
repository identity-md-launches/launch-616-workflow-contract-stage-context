# Contract ABI and integration

The generated [LaunchToken ABI](abi/LaunchToken.json) and [HackathonRegistry ABI](abi/HackathonRegistry.json) are JSON ABI arrays produced by the pinned compiler. `python3 scripts/export_abi.py --check` detects drift. All contract functions are nonpayable or view. Constructors take no arguments and no ETH.

## HackathonRegistry

| Call | Result / behavior |
| --- | --- |
| `deadline() → uint256` | Immutable UNIX timestamp in seconds; edits and registrations require `block.timestamp < deadline` |
| `entryCount() → uint256` | Number of all historical entries, including withdrawn entries |
| `entryIdOf(address) → uint256` | Permanent entry ID; zero if never registered |
| `getEntry(uint256 id) → Entry` | Complete entry; reverts for zero or an ID greater than `entryCount` |
| `register(string projectName, string repositoryUrl, string demoUrl, uint256 toolkitMask) → uint256 id` | Register caller once; IDs start at 1 |
| `update(string projectName, string repositoryUrl, string demoUrl, uint256 toolkitMask)` | Replace caller's entry metadata before the deadline |
| `withdraw()` | Permanently mark caller's entry withdrawn, including after the deadline |
| `DURATION()` | `1209600` seconds |
| `MAX_NAME_BYTES()` / `MAX_URL_BYTES()` | `64` / `200` |
| `TOOLKIT_COUNT()` / `VALID_TOOLKIT_MASK()` | `19` / `524287` |
| `ORGANISER()` | The excluded prize wallet; not an administrator |

`Entry` has these fields in ABI tuple order:

```text
address entrant
string  projectName
string  repositoryUrl
string  demoUrl
uint256 toolkitMask
bool    withdrawn
```

To enumerate, read `entryCount()` and request each ID from 1 through that count in bounded client batches. Read at one block tag for a consistent snapshot. Withdrawals never reorder or delete IDs. To show only active entries, filter `withdrawn == false`. Never interpret a withdrawn record as a free registration slot. Store large integers as bigint/string in clients.

Events:

```text
RegistryOpened(uint256 deadline)
EntryRegistered(uint256 indexed id, address indexed entrant,
                string projectName, string repositoryUrl, string demoUrl, uint256 toolkitMask)
EntryUpdated(uint256 indexed id, address indexed entrant,
             string projectName, string repositoryUrl, string demoUrl, uint256 toolkitMask)
EntryWithdrawn(uint256 indexed id, address indexed entrant)
```

Replay logs starting at the deployment block in block/transaction/log order. Registration creates a record, update replaces metadata, withdrawal sets a permanent flag. Handle chain reorganizations and reconcile with `getEntry`. For judging, use the finalized last block whose timestamp is strictly before `deadline`, preserve its block hash and entry snapshot, and check subsequent withdrawals before payout. The website should use chain time to check open/closed status; a local countdown does not guarantee inclusion before the deadline.

All registry custom errors have no arguments:

| Error | Meaning |
| --- | --- |
| `RegistrationClosed()` | Registration/update is at or after the deadline |
| `OrganiserIneligible()` | The supplied prize wallet attempted registration |
| `AlreadyRegistered()` | Caller has a permanent ID, including one already withdrawn |
| `NotRegistered()` | Caller tried to update/withdraw without an entry |
| `EntryAlreadyWithdrawn()` | Caller tried to update/withdraw a withdrawn entry |
| `InvalidEntryId()` | Requested ID is outside `1..entryCount` |
| `InvalidNameLength()` | Name is empty or longer than 64 bytes |
| `InvalidRepositoryUrlLength()` | Repository URL is empty or longer than 200 bytes |
| `InvalidDemoUrlLength()` | Demo URL is empty or longer than 200 bytes |
| `InvalidToolkitMask()` | Mask is zero or has any bit above bit 18 set |

Deadline checks precede caller and field checks for register/update. Field validation runs name, repository URL, demo URL, then mask. Withdrawal has no deadline check. Estimate gas and decode revert data rather than treating failed transactions as state changes.

Compute input lengths with `new TextEncoder().encode(value).length`, and compute masks by OR-ing `1n << BigInt(bit)` using [the catalog](toolkit.md). Only the byte count is validated on-chain; an accepted string is not a trusted or verified link. Escape text and validate HTTP(S) links in the client. Public accessibility and honest toolkit use belong to judging.

## LaunchToken

The standard ERC-20 surface is `name`, `symbol`, `decimals`, `totalSupply`, `balanceOf`, `allowance`, `approve`, `transfer`, and `transferFrom`. `transfer`, `approve` and `transferFrom` return `true` on success and revert on invalid input. The initial mint emits `Transfer(address(0), deployer, 10^27)`. Transfers emit `Transfer`; explicit approvals emit `Approval`.

This uses the vendored OpenZeppelin Contracts v5.1.0 ERC-20 implementation. A maximum `uint256` allowance is infinite and not reduced by `transferFrom`; finite allowances are reduced, without an additional `Approval` event. Clients should read `allowance` rather than reconstructing it solely from logs. Replacing a live nonzero allowance has the usual ERC-20 transaction-ordering risk; use exact amounts and revoke first where appropriate. There are no token approvals needed by the registry.

The ABI includes the inherited ERC-6093 errors (`ERC20InsufficientBalance`, `ERC20InvalidSender`, `ERC20InvalidReceiver`, `ERC20InsufficientAllowance`, `ERC20InvalidApprover`, `ERC20InvalidSpender`) with their full typed arguments. There are no public mint, burn, permit, owner, pause, fee or upgrade functions.
