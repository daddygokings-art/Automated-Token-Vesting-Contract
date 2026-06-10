# Automated Token Vesting Contract

A time-locked release mechanism for distributing tokens to team members, investors, or community contributors over a predefined schedule. Built with Foundry.

---

## Core Features

- **Linear Vesting Schedules** — Tokens released continuously using per-second mathematical calculations. Withdraw exactly the vested amount at any point.
- **Configurable Parameters** — Each beneficiary gets a unique vesting schedule with custom start time, cliff duration, total duration, and allocation.
- **Admin Security Controls** — Role-based access control ensures only the authorized admin can create schedules, update parameters, or pause the contract.
- **Pause / Emergency Stop** — Admin can pause all token releases in case of emergency.
- **Revoke with Unvested Return** — Admin can revoke a schedule and return unvested tokens to the treasury.
- **Event-Driven Architecture** — All state changes emit structured events for off-chain monitoring.
- **NatSpec Documentation** — Full Solidity NatSpec across all functions and state variables.

---

## Smart Contracts

```
src/
├── IVesting.sol           # Interface with Schedule struct, events, and function signatures
├── VestingAdmin.sol       # Admin validation, role management, pause/unpause controls
├── VestingContract.sol    # Core vesting logic, release calculations, and token management
├── MockERC20.sol          # Test-only ERC20 implementation
└── interfaces/
    └── IERC20.sol         # Minimal ERC20 interface
```

### IVesting.sol — Interface

Defines the `Schedule` struct, all events (`ScheduleCreated`, `TokensReleased`, `ScheduleRevoked`, `BeneficiaryUpdated`, `Paused`, `Unpaused`), and the external function signatures.

### VestingAdmin.sol — Access Control

Abstract contract inherited by `VestingContract` that provides:
- Admin-only modifier (`onlyAdmin`)
- Pause/unpause with `whenNotPaused` / `whenPaused` modifiers
- Admin transfer functionality

### VestingContract.sol — Core Logic

The main contract implementing all vesting functionality:

| Function | Description |
|---|---|
| `createSchedule` | Creates a new vesting schedule (admin only) |
| `release` | Transfers currently vested tokens to the beneficiary |
| `revoke` | Cancels a schedule and returns unvested tokens (admin only) |
| `vestedAmount` | View — calculates vested amount at a given timestamp |
| `releasableAmount` | View — calculates currently releasable amount |
| `updateBeneficiary` | Updates the beneficiary address for a schedule |
| `pause` / `unpause` | Emergency stop (admin only) |

---

## Vesting Math

Per-second linear interpolation with cliff support:

```
vestedAmount = totalAllocation * min(t - start, duration) / duration

if t < (start + cliff) : vestedAmount = 0
```

### Example Schedule

```
Allocation: 30,000 tokens
Duration:   365 days (31,536,000 seconds)
Cliff:      90 days (7,776,000 seconds)
Start:      t = 1,680,000,000

At cliff (t = 1,687,776,000):
  Vested = 30,000 * 7,776,000 / 31,536,000 ≈ 7,397 tokens

At full duration (t = 1,711,536,000):
  Vested = 30,000 tokens (fully vested)
```

---

## Security

- **Admin-only guards** — Schedule creation, revocation, and pausing restricted to a single admin role.
- **Transferable admin** — Admin can be transferred to a new address or multisig.
- **Pause mechanism** — Emergency stop halts `createSchedule` and `release`.
- **Revoke protection** — Once revoked, `release` returns zero; no double-revoke.
- **Input validation** — Zero-address, zero-amount, zero-duration, and cliff-exceeds-duration checks at creation.
- **ERC20 return checks** — All `transfer`/`transferFrom` calls verify the return value.

---

## Quickstart

### Prerequisites

- [Foundry](https://book.getfoundry.sh/) (forge, cast, anvil)

### Build

```bash
forge build
```

### Test

```bash
forge test -vvv
```

### Format

```bash
forge fmt
```

### Gas Snapshots

```bash
forge snapshot
```

### Deploy (local anvil)

```bash
anvil &
forge script script/Deploy.s.sol --rpc-url http://127.0.0.1:8545 --broadcast
```

---

## Tests

57 tests covering:

- **Unit tests** — Deployment, schedule creation, input validation, edge cases
- **Vesting math** — Before cliff, at cliff, midpoint, fully vested, zero cliff, post-vest
- **Release flows** — Partial release, full release, multiple beneficiaries, release by anyone
- **Revoke flows** — Before cliff, after partial release, already revoked
- **Admin controls** — Pause/unpause, admin transfer, non-admin rejection
- **Events** — All events verified with expected data
- **Fuzz tests** — 3 fuzz scenarios with 256 runs each: vesting math invariants, create-and-release consistency, vested amount monotonicity

```bash
forge test -vvv
```

---

## CI/CD

GitHub Actions workflow (`.github/workflows/test.yml`) runs on every push and pull request:

1. Checkout with submodules
2. Install Foundry
3. `forge fmt --check`
4. `forge build --sizes`
5. `forge test -vvv`

---

## Development Wave Breakdown

| Wave | Points | Focus |
|---|---|---|
| High (200) | 200 | Per-second linear release math with cliff-aware interpolation |
| Medium (150) | 150 | Admin security validation — `onlyAdmin`, pause/unpause, admin transfer |
| Trivial (100) | 100 | NatSpec documentation across all contracts |

---

## License

MIT
