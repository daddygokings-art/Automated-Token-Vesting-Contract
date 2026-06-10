# Automated Token Vesting Contract

A time-locked release mechanism for distributing tokens to team members, investors, or community contributors over a predefined schedule. Built as a **Soroban** smart contract on **Stellar**, written in Rust.

---

## Core Features

- **Linear Vesting Schedules** — Tokens released continuously using per-second mathematical calculations. Withdraw exactly the vested amount at any point.
- **Configurable Parameters** — Each beneficiary gets a unique vesting schedule with custom start time, cliff duration, total duration, and allocation.
- **Admin Security Controls** — `require_auth()`-based access control ensures only the authorized admin can create schedules, update parameters, or pause the contract.
- **Pause / Emergency Stop** — Admin can pause all token releases in case of emergency.
- **Revoke with Unvested Return** — Admin can revoke a schedule and return unvested tokens to the treasury.
- **Event-Driven Architecture** — All state changes emit structured events for off-chain monitoring.
- **Stellar Asset Integration** — Works with any Stellar Asset Contract (SAC) token.

---

## Smart Contract

```
contracts/token-vesting/
├── Cargo.toml
└── src/
    ├── lib.rs    # Contract logic, storage, math, and events
    └── test.rs   # 26 unit tests covering all functionality
```

### Public Functions

| Function | Description | Access |
|---|---|---|
| `create_schedule` | Creates a new vesting schedule and transfers tokens from admin | Admin (auth) |
| `release` | Transfers currently vested tokens to the beneficiary | Anyone |
| `revoke` | Cancels a schedule and returns unvested tokens | Admin (auth) |
| `vested_amount` | View — calculates vested amount at a given timestamp | Anyone |
| `releasable_amount` | View — calculates currently releasable amount | Anyone |
| `update_beneficiary` | Updates the beneficiary address for a schedule | Beneficiary or admin (auth) |
| `pause` / `unpause` | Emergency stop | Admin (auth) |
| `transfer_admin` | Transfers admin role to a new address | Admin (auth) |
| `get_schedule` | View — returns schedule details | Anyone |
| `beneficiary_schedules` | View — returns all schedule IDs for a beneficiary | Anyone |

### Storage Model

| Key | Value |
|---|---|
| `Admin` | Contract admin address |
| `Token` | Token contract address |
| `Paused` | Boolean pause flag |
| `ScheduleCount` | Total number of schedules created |
| `Schedule(u32)` | Individual vesting schedule by ID |
| `BeneficiarySchedules(Address)` | List of schedule IDs for a beneficiary |

---

## Vesting Math

Per-second linear interpolation with cliff support:

```
vestedAmount = totalAllocation * min(t - start, duration) / duration

if t < (start + cliff): vestedAmount = 0
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
  Vested = 30,000 (fully vested)
```

---

## Security

- **`require_auth()`** — Admin functions require Stellar auth, verified at the protocol level.
- **Input validation** — Zero-amount, zero-duration, and cliff-exceeds-duration checks at creation.
- **Pause mechanism** — Emergency stop halts `create_schedule` and `release`.
- **Revoke protection** — Once revoked, `release` returns zero; no double-revoke.
- **Overflow-safe math** — Uses Rust's checked arithmetic; `overflow-checks = true` in release profile.
- **Transferable admin** — Admin role can be transferred to a multisig or new address.

---

## Quickstart

### Prerequisites

- [Rust](https://rustup.rs/) 1.84+
- wasm32v1-none target (`rustup target add wasm32v1-none`)
- [Stellar CLI](https://github.com/stellar/stellar-cli) (optional, for deployment)

### Build

```bash
cargo build --target wasm32v1-none --release
```

### Test

```bash
cargo test
```

### Optimize WASM

```bash
stellar contract optimize \
  --wasm target/wasm32v1-none/release/token_vesting.wasm \
  --wasm-out target/wasm32v1-none/release/token_vesting_optimized.wasm
```

### Deploy (testnet)

```bash
stellar contract deploy \
  --wasm target/wasm32v1-none/release/token_vesting_optimized.wasm \
  --salt $(openssl rand -hex 32) \
  -- \
  --admin <ADMIN_ADDRESS> \
  --token <TOKEN_CONTRACT_ID>
```

---

## Tests

26 unit tests covering:

- **Deployment** — Admin, token, pause state, schedule count
- **Input validation** — Zero amount, zero duration, cliff exceeds duration, non-admin rejection
- **Vesting math** — Before cliff, at cliff, fully vested, never exceeds total
- **Release flows** — Partial release, full release, before cliff, after revoke
- **Revoke flows** — Before cliff, after partial release, non-admin rejection
- **Admin controls** — Pause/unpause, paused blocks schedule creation, admin transfer
- **Beneficiary management** — Update beneficiary, beneficiary schedules tracking, multiple schedules

```bash
cargo test
```

---

## CI/CD

GitHub Actions workflow (`.github/workflows/test.yml`) runs on every push and pull request:

1. Checkout + Rust toolchain with `wasm32v1-none` target
2. Cargo cache for faster builds
3. `cargo test` — all 26 tests
4. `cargo build --target wasm32v1-none --release` — production WASM

---

## Development Wave Breakdown

| Wave | Points | Focus |
|---|---|---|
| High (200) | 200 | Per-second linear release math with cliff-aware interpolation in Rust |
| Medium (150) | 150 | Admin security validation — `require_auth()`, pause/unpause, admin transfer |
| Trivial (100) | 100 | Documentation — Rustdoc comments across all public functions |

---

## License

MIT
