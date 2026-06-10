#![cfg(test)]

use crate::{VestingContract, VestingContractClient};
use soroban_sdk::testutils::{Address as _, Ledger};
use soroban_sdk::{token, Address, Env};

fn create_token_and_vesting(env: &Env) -> (VestingContractClient, token::StellarAssetClient<'_>, Address, Address) {
    let admin = Address::generate(env);

    let token_addr = env.register_stellar_asset_contract(admin.clone());
    let token_client = token::StellarAssetClient::new(env, &token_addr);

    let vesting_id = env.register(VestingContract, (admin.clone(), token_addr.clone()));
    let vesting_client = VestingContractClient::new(env, &vesting_id);

    (vesting_client, token_client, admin, token_addr)
}

fn setup(
    vesting: &VestingContractClient,
    token_client: &token::StellarAssetClient,
    admin: &Address,
    ben: &Address,
    amount: i128,
    cliff: u64,
    duration: u64,
    env: &Env,
) -> u32 {
    token_client.mint(admin, &(amount + 1_000_000_000));
    let start = env.ledger().timestamp();
    vesting.create_schedule(admin, ben, &amount, &start, &cliff, &duration)
}

#[test]
fn test_deployment() {
    let env = Env::default();
    env.mock_all_auths();
    let (vesting, _tc, admin, token_addr) = create_token_and_vesting(&env);
    assert_eq!(vesting.admin(), admin);
    assert_eq!(vesting.token(), token_addr);
    assert!(!vesting.paused());
    assert_eq!(vesting.schedule_count(), 0);
}

#[test]
fn test_create_schedule() {
    let env = Env::default();
    env.mock_all_auths();
    let (vesting, tc, admin, _ta) = create_token_and_vesting(&env);
    let ben = Address::generate(&env);

    let total = 50_000_000_000i128;
    let start = env.ledger().timestamp();
    let cliff: u64 = 7_776_000;
    let duration: u64 = 31_536_000;

    let id = setup(&vesting, &tc, &admin, &ben, total, cliff, duration, &env);
    assert_eq!(id, 0);
    assert_eq!(vesting.schedule_count(), 1);

    let sched = vesting.get_schedule(&id);
    assert_eq!(sched.beneficiary, ben);
    assert_eq!(sched.total_amount, total);
    assert_eq!(sched.released_amount, 0);
    assert_eq!(sched.cliff, start + cliff);
    assert_eq!(sched.duration, duration);
    assert!(!sched.revoked);
}

#[test]
fn test_create_schedule_not_admin() {
    let env = Env::default();
    env.mock_all_auths();
    let (vesting, _tc, _admin, _ta) = create_token_and_vesting(&env);
    let caller = Address::generate(&env);
    let ben = Address::generate(&env);

    let start = env.ledger().timestamp();
    let result = vesting.try_create_schedule(&caller, &ben, &50_000_000_000, &start, &7_776_000, &31_536_000);
    assert!(result.is_err());
}

#[test]
fn test_create_schedule_zero_amount() {
    let env = Env::default();
    env.mock_all_auths();
    let (vesting, _tc, admin, _ta) = create_token_and_vesting(&env);
    let ben = Address::generate(&env);
    let start = env.ledger().timestamp();

    let result = vesting.try_create_schedule(&admin, &ben, &0, &start, &7_776_000, &31_536_000);
    assert!(result.is_err());
}

#[test]
fn test_create_schedule_zero_duration() {
    let env = Env::default();
    env.mock_all_auths();
    let (vesting, _tc, admin, _ta) = create_token_and_vesting(&env);
    let ben = Address::generate(&env);
    let start = env.ledger().timestamp();

    let result = vesting.try_create_schedule(&admin, &ben, &50_000_000_000, &start, &0, &0);
    assert!(result.is_err());
}

#[test]
fn test_create_schedule_cliff_exceeds_duration() {
    let env = Env::default();
    env.mock_all_auths();
    let (vesting, _tc, admin, _ta) = create_token_and_vesting(&env);
    let ben = Address::generate(&env);
    let start = env.ledger().timestamp();

    let result = vesting.try_create_schedule(&admin, &ben, &50_000_000_000, &start, &100, &50);
    assert!(result.is_err());
}

#[test]
fn test_vested_amount_before_cliff() {
    let env = Env::default();
    env.mock_all_auths();
    let (vesting, tc, admin, _ta) = create_token_and_vesting(&env);
    let ben = Address::generate(&env);
    let start = env.ledger().timestamp();
    let id = setup(&vesting, &tc, &admin, &ben, 50_000_000_000, 7_776_000, 31_536_000, &env);
    assert_eq!(vesting.vested_amount(&id, &(start + 7_776_000 - 1)), 0);
}

#[test]
fn test_vested_amount_at_cliff() {
    let env = Env::default();
    env.mock_all_auths();
    let (vesting, tc, admin, _ta) = create_token_and_vesting(&env);
    let ben = Address::generate(&env);
    let start = env.ledger().timestamp();
    let total: i128 = 50_000_000_000;
    let cliff: u64 = 7_776_000;
    let duration: u64 = 31_536_000;
    let id = setup(&vesting, &tc, &admin, &ben, total, cliff, duration, &env);

    let vested = vesting.vested_amount(&id, &(start + cliff));
    let expected = (total * cliff as i128) / duration as i128;
    assert_eq!(vested, expected);
}

#[test]
fn test_vested_amount_fully_vested() {
    let env = Env::default();
    env.mock_all_auths();
    let (vesting, tc, admin, _ta) = create_token_and_vesting(&env);
    let ben = Address::generate(&env);
    let start = env.ledger().timestamp();
    let total: i128 = 50_000_000_000;
    let duration: u64 = 31_536_000;
    let id = setup(&vesting, &tc, &admin, &ben, total, 0, duration, &env);

    assert_eq!(vesting.vested_amount(&id, &(start + duration)), total);
}

#[test]
fn test_release_after_cliff() {
    let env = Env::default();
    env.mock_all_auths();
    let (vesting, tc, admin, _ta) = create_token_and_vesting(&env);
    let ben = Address::generate(&env);
    let start = env.ledger().timestamp();
    let id = setup(&vesting, &tc, &admin, &ben, 50_000_000_000, 7_776_000, 31_536_000, &env);

    env.ledger().set_timestamp(start + 7_776_000 + 30 * 24 * 60 * 60);

    let releasable = vesting.releasable_amount(&id);
    assert!(releasable > 0);
    assert!(releasable < 50_000_000_000);

    let released = vesting.release(&id);
    assert_eq!(released, releasable);

    let sched = vesting.get_schedule(&id);
    assert_eq!(sched.released_amount, released);
}

#[test]
fn test_release_full() {
    let env = Env::default();
    env.mock_all_auths();
    let (vesting, tc, admin, _ta) = create_token_and_vesting(&env);
    let ben = Address::generate(&env);
    let start = env.ledger().timestamp();
    let total: i128 = 50_000_000_000;
    let duration: u64 = 31_536_000;
    let id = setup(&vesting, &tc, &admin, &ben, total, 0, duration, &env);

    env.ledger().set_timestamp(start + duration);
    assert_eq!(vesting.release(&id), total);

    let sched = vesting.get_schedule(&id);
    assert_eq!(sched.released_amount, total);
}

#[test]
fn test_release_before_cliff() {
    let env = Env::default();
    env.mock_all_auths();
    let (vesting, tc, admin, _ta) = create_token_and_vesting(&env);
    let ben = Address::generate(&env);
    let _id = setup(&vesting, &tc, &admin, &ben, 50_000_000_000, 7_776_000, 31_536_000, &env);

    let result = vesting.try_release(&0);
    assert!(result.is_err());
}

#[test]
fn test_revoke_before_cliff() {
    let env = Env::default();
    env.mock_all_auths();
    let (vesting, tc, admin, _ta) = create_token_and_vesting(&env);
    let ben = Address::generate(&env);
    let id = setup(&vesting, &tc, &admin, &ben, 50_000_000_000, 7_776_000, 31_536_000, &env);

    let result = vesting.try_revoke(&admin, &id);
    assert!(result.is_ok());

    let sched = vesting.get_schedule(&id);
    assert!(sched.revoked);
}

#[test]
fn test_revoke_after_partial_release() {
    let env = Env::default();
    env.mock_all_auths();
    let (vesting, tc, admin, _ta) = create_token_and_vesting(&env);
    let ben = Address::generate(&env);
    let start = env.ledger().timestamp();
    let id = setup(&vesting, &tc, &admin, &ben, 50_000_000_000, 7_776_000, 31_536_000, &env);

    env.ledger().set_timestamp(start + 7_776_000 + 30 * 24 * 60 * 60);
    let released = vesting.release(&id);

    let result = vesting.try_revoke(&admin, &id);
    assert!(result.is_ok());

    let sched = vesting.get_schedule(&id);
    assert!(sched.revoked);
    assert_eq!(sched.released_amount, released);
}

#[test]
fn test_revoke_not_admin() {
    let env = Env::default();
    env.mock_all_auths();
    let (vesting, tc, admin, _ta) = create_token_and_vesting(&env);
    let ben = Address::generate(&env);
    let id = setup(&vesting, &tc, &admin, &ben, 50_000_000_000, 0, 31_536_000, &env);

    let non_admin = Address::generate(&env);
    let result = vesting.try_revoke(&non_admin, &id);
    assert!(result.is_err());
}

#[test]
fn test_update_beneficiary() {
    let env = Env::default();
    env.mock_all_auths();
    let (vesting, tc, admin, _ta) = create_token_and_vesting(&env);
    let ben = Address::generate(&env);
    let id = setup(&vesting, &tc, &admin, &ben, 50_000_000_000, 0, 31_536_000, &env);

    let new_ben = Address::generate(&env);
    let result = vesting.try_update_beneficiary(&ben, &id, &new_ben);
    assert!(result.is_ok());

    let sched = vesting.get_schedule(&id);
    assert_eq!(sched.beneficiary, new_ben);

    assert_eq!(vesting.beneficiary_schedules(&new_ben).len(), 1);
    assert_eq!(vesting.beneficiary_schedules(&ben).len(), 0);
}

#[test]
fn test_pause_and_unpause() {
    let env = Env::default();
    env.mock_all_auths();
    let (vesting, _tc, admin, _ta) = create_token_and_vesting(&env);

    let r = vesting.try_pause(&admin);
    assert!(r.is_ok());
    assert!(vesting.paused());

    let r = vesting.try_unpause(&admin);
    assert!(r.is_ok());
    assert!(!vesting.paused());
}

#[test]
fn test_pause_not_admin() {
    let env = Env::default();
    env.mock_all_auths();
    let (vesting, ..) = create_token_and_vesting(&env);
    let non_admin = Address::generate(&env);

    let result = vesting.try_pause(&non_admin);
    assert!(result.is_err());
}

#[test]
fn test_create_schedule_when_paused() {
    let env = Env::default();
    env.mock_all_auths();
    let (vesting, tc, admin, _ta) = create_token_and_vesting(&env);

    vesting.pause(&admin);

    let ben = Address::generate(&env);
    let start = env.ledger().timestamp();
    let result = vesting.try_create_schedule(&admin, &ben, &50_000_000_000, &start, &0, &31_536_000);
    assert!(result.is_err());
}

#[test]
fn test_transfer_admin() {
    let env = Env::default();
    env.mock_all_auths();
    let (vesting, _tc, admin, _ta) = create_token_and_vesting(&env);

    let new_admin = Address::generate(&env);
    let r = vesting.try_transfer_admin(&admin, &new_admin);
    assert!(r.is_ok());
    assert_eq!(vesting.admin(), new_admin);
}

#[test]
fn test_transfer_admin_not_admin() {
    let env = Env::default();
    env.mock_all_auths();
    let (vesting, _tc, _admin, _ta) = create_token_and_vesting(&env);

    let caller = Address::generate(&env);
    let new_admin = Address::generate(&env);
    let result = vesting.try_transfer_admin(&caller, &new_admin);
    assert!(result.is_err());
}

#[test]
fn test_beneficiary_schedules() {
    let env = Env::default();
    env.mock_all_auths();
    let (vesting, tc, admin, _ta) = create_token_and_vesting(&env);
    let ben = Address::generate(&env);

    let start = env.ledger().timestamp();
    tc.mint(&admin, &(100_000_000_000));

    let _id1 = vesting.create_schedule(&admin, &ben, &50_000_000_000, &start, &0, &31_536_000);
    let _id2 = vesting.create_schedule(&admin, &ben, &50_000_000_000, &start, &0, &31_536_000);

    let schedules = vesting.beneficiary_schedules(&ben);
    assert_eq!(schedules.len(), 2);
}

#[test]
fn test_multiple_schedules() {
    let env = Env::default();
    env.mock_all_auths();
    let (vesting, tc, admin, _ta) = create_token_and_vesting(&env);
    let ben1 = Address::generate(&env);
    let ben2 = Address::generate(&env);

    let start = env.ledger().timestamp();
    tc.mint(&admin, &(100_000_000_000));

    let id1 = vesting.create_schedule(&admin, &ben1, &50_000_000_000, &start, &0, &31_536_000);
    let id2 = vesting.create_schedule(&admin, &ben2, &30_000_000_000, &start, &0, &15_000_000);

    assert_eq!(id1, 0);
    assert_eq!(id2, 1);
    assert_eq!(vesting.schedule_count(), 2);
}

#[test]
fn test_vested_amount_never_exceeds_total() {
    let env = Env::default();
    env.mock_all_auths();
    let (vesting, tc, admin, _ta) = create_token_and_vesting(&env);
    let ben = Address::generate(&env);

    let total: i128 = 50_000_000_000;
    let start = env.ledger().timestamp();
    let id = setup(&vesting, &tc, &admin, &ben, total, 0, 31_536_000, &env);

    let far = start + 100 * 365 * 24 * 60 * 60;
    assert_eq!(vesting.vested_amount(&id, &far), total);
}

#[test]
fn test_releasable_zero_after_full_release() {
    let env = Env::default();
    env.mock_all_auths();
    let (vesting, tc, admin, _ta) = create_token_and_vesting(&env);
    let ben = Address::generate(&env);
    let start = env.ledger().timestamp();
    let duration: u64 = 31_536_000;
    let id = setup(&vesting, &tc, &admin, &ben, 50_000_000_000, 0, duration, &env);

    env.ledger().set_timestamp(start + duration);
    vesting.release(&id);
    assert_eq!(vesting.releasable_amount(&id), 0);
}

#[test]
fn test_releasable_zero_after_revoke() {
    let env = Env::default();
    env.mock_all_auths();
    let (vesting, tc, admin, _ta) = create_token_and_vesting(&env);
    let ben = Address::generate(&env);
    let id = setup(&vesting, &tc, &admin, &ben, 50_000_000_000, 0, 31_536_000, &env);

    vesting.revoke(&admin, &id);
    assert_eq!(vesting.releasable_amount(&id), 0);
}
