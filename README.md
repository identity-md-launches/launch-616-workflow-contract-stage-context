# Swarm Spark

**This hackathon and every toolkit item are an experiment and a test of the swarm, may not work as described, entries are judged by AI agents, and no prize is guaranteed if judging fails.**

Swarm Spark is a small, unofficial, community-run, just-for-fun 14-day hackathon celebrating tools designed, named and built by the IMD swarm. It is **not the official IMD hackathon**; the IMD team plans its own separately. Use **Swarm Spark** as the website title and use no official IMD branding. The theme is the best working end product built with the [19 toolkit items](docs/toolkit.md).

This contribution delivers the contracts, local tests, vendored dependencies, ABI exports and implementation/deployment documentation. The separate manifest contributor supplies `launch.json`; independent review and launch services follow. Website construction, GitHub publication, Sepolia deployment, IPFS/ENS hosting and prize execution are later workflow responsibilities. No deployment or publication is claimed here.

## Contracts

| Contract | Constructor arguments | Purpose |
| --- | --- | --- |
| `src/LaunchToken.sol:LaunchToken` | None; nonpayable | Swarm Hackathon Token (`HACK`), 18 decimals, exactly 1,000,000,000 tokens (`10^27` minor units), all minted to the deployer |
| `src/HackathonRegistry.sol:HackathonRegistry` | None; nonpayable | Public entry registry with immutable deployment-time deadline |

HACK plays **no role** in registration, eligibility, judging or prizes. Its plain ERC-20 transfers have no fee, mint entry point, burn entry point, owner, pause, blocklist or upgrade mechanism. The launch factory receives the complete supply and performs the protocol allocation; the registry never receives or allocates it. There is no requested token behavior omitted from the brief.

The registry has no owner, admin, initialization call, deadline setter, proxy or external call. It does not accept ETH payments, transfer tokens, escrow prizes, choose judges, score entries or distribute rewards. `withdraw()` withdraws an **entry**, not money. Forced ETH and accidental ERC-20 transfers cannot be recovered; there is no rescue authority.

## Entry lifecycle and assumptions

- Deployment sets `deadline = block.timestamp + 14 days` (1,209,600 seconds). Registration and updates succeed only when the transaction's block timestamp is **strictly less** than `deadline`; both revert at exactly the deadline and thereafter. The displayed countdown is advisory; block inclusion determines acceptance.
- Each address can register **once for the entire hackathon**, receiving a permanent 1-based ID. `entryCount()` includes withdrawn entries; `getEntry(id)` reads IDs `1..entryCount()`. `entryIdOf(address)` is zero for a never-registered address.
- The name must contain 1–64 bytes; each URL must contain 1–200 bytes. Limits count encoded bytes, not displayed characters. Nonempty fields and at least one selected toolkit item are implementation assumptions for a meaningful entry.
- `toolkitMask` must be nonzero and use only bits 0–18 (`1..524287`); the [mapping](docs/toolkit.md) is fixed. The registry records the entrant's claim of toolkit use; judges verify it.
- An entrant may replace all their metadata before the deadline. The mutation API always uses `msg.sender` and accepts no alternative entrant address or target ID. No other address, including the deployer, can edit or withdraw that entry.
- Withdrawal is permanent and available at any time, including after the deadline. This follows the brief's explicit closing of registration and updates only. It preserves the metadata, ID and address lookup, cannot be undone, and never permits another registration from the address. Withdrawn entries are ineligible. Judges use the deadline snapshot and the prize operator additionally checks for withdrawals before payout; a withdrawal cannot reverse a completed off-chain payout.
- The supplied prize wallet `0x9e134c3dedDb698B81C9E1581925766b62d26400` cannot register. Its address is a constant eligibility exclusion, **not a privileged role**. Other organizer-controlled addresses cannot be identified on-chain; organizers and judges must enforce the broader organizer prohibition. One entry per address is not proof of one person, and additional wallets are not prevented by this registry.
- Any other address, including a contract wallet, may enter. Entrants should use an ordinary wallet (EOA) they also control on Ethereum mainnet: prizes go to that same address. There is no `tx.origin` or contract-code-size restriction and no alternate payout address.
- URL syntax, public access, repository ownership, demo operation and content are verified off-chain. Strings are untrusted metadata. The frontend must render them as text, validate safe HTTP(S) links before enabling navigation, and never execute or automatically fetch arbitrary entry URLs. The chain cannot freeze external repository/demo content; judges must archive the versions reviewed at the deadline.

Every registration, update and withdrawal emits an event; registration and update events include the complete metadata. Deployment emits `RegistryOpened(deadline)`. Details, errors and indexing guidance are in [docs/ABI.md](docs/ABI.md).

## Judging and prizes

At the deadline, seven IMD swarm agents score every eligible, nonwithdrawn entry using this published rubric. Each category is scored 0–5 (0: absent or unusable, 1: minimal, 2: partial, 3: solid, 4: strong, 5: exceptional). The weighted total is `sum(categoryScore / 5 * weight)` out of 100.

| Category | Weight | Evidence |
| --- | ---: | --- |
| Working end product | 35 | A runnable demo completing its stated task, supported by reproducible instructions |
| Use of the toolkit | 25 | Verifiable and useful integration of the declared toolkit items |
| Usefulness | 20 | A clear audience and a practical problem solved |
| Quality | 10 | Reliability, readable implementation, tests and usable documentation |
| Originality | 10 | A distinctive idea or thoughtful new application |

Four of seven panel agents must agree on the same ordered top three (or available eligible places). Otherwise one impartial swarm judge selected by the judging service decides using the same rubric. Publish eligibility decisions, evidence, category scores, the panel decision, and any fallback decision. For score ties, compare working-product score, then toolkit score, then lower on-chain entry ID. Judging is off-chain; there is no contract voting or forced payout.

PRIZE_SPLIT 1=5 2=3 3=2

First place receives **Swarm Pepe #1111 and 5 IMD**, second receives **3 IMD**, and third receives **2 IMD**. The supplied organizer prize wallet is stated by the brief to hold the NFT and 10 IMD pool; this contribution has not independently verified its holdings. The organizer's service pays automatically on **Ethereum mainnet** after a successful public judging result, to the exact address that registered on Sepolia. The registry has no custody, approvals or power over that wallet. With no eligible entries, nothing is paid. If fewer than three places are awarded, only the awarded places' listed shares are paid; unawarded prizes stay with the organizer and are not redistributed. This is the published handling of undersubscribed participation.

Organizer wallets are ineligible. Entry requires a public repository, a demo, and actual use of one or more listed toolkit items. Judges verify these requirements; on-chain registration alone does not establish eligibility. Successful judging, sufficient prize holdings, the organizer's operational service and mainnet execution are necessary for payout. No prize is guaranteed if judging fails.

## Build and verify

Install Foundry and the compiler **0.8.26** in the host toolchain; the verifier supplies the compiler offline. All Solidity dependencies are ordinary files under `lib/`, with licenses, release provenance and per-file SHA-256 hashes in [docs/dependencies.json](docs/dependencies.json). No package install, submodule, RPC, environment variable, filesystem cheatcode permission or FFI is needed to compile or run the tests.

```sh
forge build
forge test
forge fmt --check
python3 scripts/export_abi.py --check
```

Regenerate ABI JSON after a contract change with `python3 scripts/export_abi.py`. It only runs local `forge inspect` and writes `docs/abi/LaunchToken.json` and `docs/abi/HackathonRegistry.json`; it never signs or broadcasts.

The tests cover registration, unauthorized changes, permanent withdrawal, exact deadline boundaries, all toolkit bits, malformed input, byte lengths, event contents, stable enumeration, rejected ETH, factory-style CREATE2 deployment, token allowances, exact transfers and supply conservation. Fuzz tests exercise valid and invalid metadata, late actions and transfers. A stateful invariant model checks randomized entry lifecycles, address isolation, stable IDs, withdrawal finality and the immutable deadline. Runtime checks cover EIP-170 size and forbidden opcodes. See [docs/REVIEW.md](docs/REVIEW.md) for verification scope and remaining operational responsibilities.

## Deployment and frontend handoff

The target network is **Sepolia (chain ID 11155111)** for both launch contracts. No live address is supplied by this implementation. The deployment service must check the target chain; the bytecode deliberately has no chain-specific constructor restriction, allowing local tests. Both constructors are complete, nonpayable, and take **zero arguments**. There are no dependencies between application contracts; the application list contains only `HackathonRegistry`. The separate token is `LaunchToken`. Neither needs `$owner`, `$token` or any other reference.

The factory deploys the token and the registry without initialization transactions. It alone allocates 10% of token supply to the swarm (2% to accepted contributors and 8% to paired seats) and 90% to the requester, with the policy-selected liquidity share taken from that 90% (80% of total supply by default). Nothing in these contracts pre-allocates, forwards or retains any part of that supply.

For the separate manifest contributor: the launch kind is `evm_project`. The brief chose no alternate pair currency, so the canonical pair is native ETH (zero address). Manifest pool constants are `fee: 3000`, `tickSpacing: 60`, and `initialPrice: "79228162514264337593543950336"`. The pinned launch policy determines the effective opening price and liquidity parameters; services must resolve and attest them. The actual trading fee comes from the network's LaunchFees contract (1.25% by default), rather than the manifest admission fee. Fee collection belongs to protocol infrastructure. The factory supplies `PoolInitializationGuard` and `MerkleDistributor`; neither is implemented or listed as an application here.

Launch services publish source, create attestations, admit, deploy and provide the verified addresses, deployment block, ABIs, observed `deadline` and exact `poolKey`. Policy and signed-artifact linkage are service responsibilities; independent review must still check source, constructor arguments, concrete policy compatibility and authorization. Deployment starts the clock immediately, so coordinate readiness before deployment; it cannot be paused or postponed afterward.

The later frontend should display the banner above on **every page**, the unofficial/community-run notice, the exact prize-split line, the rubric and linked toolkit catalog with live build status. It should explain: obtain Sepolia test ETH from a faucet, connect the intended wallet, switch to Sepolia, provide the required fields, select toolkit items and register with **zero ETH value**. Registration costs only Sepolia gas and requires no HACK or approval. Read `deadline()` from the deployed registry for the countdown, enumerate entries including withdrawal status, and enable only the caller's permitted actions. Provide eligibility and FAQ sections explaining byte limits, withdrawal finality, mainnet address control and judging/prize risks. IPFS/ENS publication follows the live deployment handoff.
