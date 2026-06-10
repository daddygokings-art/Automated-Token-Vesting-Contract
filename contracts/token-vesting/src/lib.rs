#![no_std]

use soroban_sdk::token::TokenClient;
use soroban_sdk::{contract, contracterror, contractimpl, contracttype, symbol_short, Address, Env, Vec};

#[contracterror]
#[derive(Copy, Clone, Debug, Eq, PartialEq)]
pub enum VestingError {
    NotAdmin = 1,
    AlreadyPaused = 2,
    NotPaused = 3,
    Paused = 4,
    ZeroAmount = 5,
    ZeroDuration = 6,
    CliffExceedsDuration = 7,
    ScheduleNotFound = 8,
    AlreadyRevoked = 9,
    NoTokensReleasable = 10,
    InsufficientTransfer = 11,
    NotBeneficiaryOrAdmin = 12,
    ScheduleRevoked = 13,
}

#[contracttype]
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct VestingSchedule {
    pub beneficiary: Address,
    pub revoker: Address,
    pub total_amount: i128,
    pub released_amount: i128,
    pub start: u64,
    pub cliff: u64,
    pub duration: u64,
    pub revoked: bool,
}

#[contracttype]
#[derive(Clone)]
enum DataKey {
    Admin,
    Token,
    Paused,
    ScheduleCount,
    Schedule(u32),
    BeneficiarySchedules(Address),
}



#[contract]
pub struct VestingContract;

#[contractimpl]
impl VestingContract {
    pub fn __constructor(env: Env, admin: Address, token: Address) {
        env.storage().instance().set(&DataKey::Admin, &admin);
        env.storage().instance().set(&DataKey::Token, &token);
        env.storage().instance().set(&DataKey::Paused, &false);
        env.storage().instance().set(&DataKey::ScheduleCount, &0u32);
    }

    pub fn admin(env: &Env) -> Address {
        env.storage().instance().get(&DataKey::Admin).unwrap()
    }

    pub fn token(env: &Env) -> Address {
        env.storage().instance().get(&DataKey::Token).unwrap()
    }

    pub fn paused(env: &Env) -> bool {
        env.storage().instance().get(&DataKey::Paused).unwrap_or(false)
    }

    pub fn schedule_count(env: &Env) -> u32 {
        env.storage().instance().get(&DataKey::ScheduleCount).unwrap_or(0)
    }

    fn is_admin(env: &Env, addr: &Address) -> bool {
        addr == &Self::admin(env)
    }

    fn check_admin(env: &Env, addr: &Address) -> Result<(), VestingError> {
        if Self::is_admin(env, addr) {
            Ok(())
        } else {
            Err(VestingError::NotAdmin)
        }
    }

    fn check_not_paused(env: &Env) -> Result<(), VestingError> {
        if Self::paused(env) {
            Err(VestingError::Paused)
        } else {
            Ok(())
        }
    }

    pub fn transfer_admin(env: &Env, caller: Address, new_admin: Address) -> Result<(), VestingError> {
        caller.require_auth();
        Self::check_admin(env, &caller)?;
        env.storage().instance().set(&DataKey::Admin, &new_admin);
        Ok(())
    }

    pub fn pause(env: &Env, caller: Address) -> Result<(), VestingError> {
        Self::check_admin(env, &caller)?;
        if Self::paused(env) {
            return Err(VestingError::AlreadyPaused);
        }
        env.storage().instance().set(&DataKey::Paused, &true);
        env.events().publish((symbol_short!("pause"),), caller.clone());
        Ok(())
    }

    pub fn unpause(env: &Env, caller: Address) -> Result<(), VestingError> {
        Self::check_admin(env, &caller)?;
        if !Self::paused(env) {
            return Err(VestingError::NotPaused);
        }
        env.storage().instance().set(&DataKey::Paused, &false);
        env.events().publish((symbol_short!("unpause"),), caller.clone());
        Ok(())
    }

    pub fn create_schedule(
        env: Env,
        caller: Address,
        beneficiary: Address,
        total_amount: i128,
        start: u64,
        cliff: u64,
        duration: u64,
    ) -> Result<u32, VestingError> {
        caller.require_auth();
        Self::check_admin(&env, &caller)?;
        Self::check_not_paused(&env)?;

        if total_amount <= 0 {
            return Err(VestingError::ZeroAmount);
        }
        if duration == 0 {
            return Err(VestingError::ZeroDuration);
        }
        if cliff > duration {
            return Err(VestingError::CliffExceedsDuration);
        }

        let token_addr = Self::token(&env);
        let token_client = TokenClient::new(&env, &token_addr);

        let balance_before = token_client.balance(&env.current_contract_address());
        token_client.transfer(&caller, &env.current_contract_address(), &total_amount);
        let balance_after = token_client.balance(&env.current_contract_address());
        let actual_received = balance_after - balance_before;

        if actual_received < total_amount {
            return Err(VestingError::InsufficientTransfer);
        }

        let count = Self::schedule_count(&env);
        let schedule_id = count;

        let schedule = VestingSchedule {
            beneficiary: beneficiary.clone(),
            revoker: caller.clone(),
            total_amount: actual_received,
            released_amount: 0,
            start,
            cliff: start + cliff,
            duration,
            revoked: false,
        };

        env.storage().instance().set(&DataKey::Schedule(schedule_id), &schedule);
        env.storage().instance().set(&DataKey::ScheduleCount, &(count + 1));

        let mut ben_schedules: Vec<u32> = env
            .storage()
            .instance()
            .get(&DataKey::BeneficiarySchedules(beneficiary.clone()))
            .unwrap_or(Vec::new(&env));
        ben_schedules.push_back(schedule_id);
        env.storage()
            .instance()
            .set(&DataKey::BeneficiarySchedules(beneficiary.clone()), &ben_schedules);

        env.events().publish(
            (symbol_short!("create"), symbol_short!("schedule")),
            (schedule_id, beneficiary, actual_received, start),
        );

        Ok(schedule_id)
    }

    pub fn release(env: Env, schedule_id: u32) -> Result<i128, VestingError> {
        Self::check_not_paused(&env)?;

        let mut schedule: VestingSchedule = env
            .storage()
            .instance()
            .get(&DataKey::Schedule(schedule_id))
            .ok_or(VestingError::ScheduleNotFound)?;

        let amount = Self::releasable_amount_inner(&schedule, &env)?;
        if amount == 0 {
            return Err(VestingError::NoTokensReleasable);
        }

        schedule.released_amount += amount;
        env.storage()
            .instance()
            .set(&DataKey::Schedule(schedule_id), &schedule);

        let token_addr = Self::token(&env);
        let token_client = TokenClient::new(&env, &token_addr);
        token_client.transfer(&env.current_contract_address(), &schedule.beneficiary, &amount);

        env.events().publish(
            (symbol_short!("release"),),
            (schedule_id, schedule.beneficiary.clone(), amount),
        );

        Ok(amount)
    }

    pub fn revoke(env: Env, caller: Address, schedule_id: u32) -> Result<(), VestingError> {
        caller.require_auth();
        Self::check_admin(&env, &caller)?;

        let mut schedule: VestingSchedule = env
            .storage()
            .instance()
            .get(&DataKey::Schedule(schedule_id))
            .ok_or(VestingError::ScheduleNotFound)?;

        if schedule.revoked {
            return Err(VestingError::AlreadyRevoked);
        }

        schedule.revoked = true;
        schedule.revoker = caller.clone();

        let unvested = schedule.total_amount - schedule.released_amount;
        if unvested > 0 {
            let token_addr = Self::token(&env);
            let token_client = TokenClient::new(&env, &token_addr);
            token_client.transfer(&env.current_contract_address(), &caller, &unvested);
        }

        env.storage()
            .instance()
            .set(&DataKey::Schedule(schedule_id), &schedule);

        env.events().publish(
            (symbol_short!("revoke"),),
            (schedule_id, caller.clone(), unvested),
        );

        Ok(())
    }

    pub fn update_beneficiary(
        env: Env,
        caller: Address,
        schedule_id: u32,
        new_beneficiary: Address,
    ) -> Result<(), VestingError> {
        caller.require_auth();
        let mut schedule: VestingSchedule = env
            .storage()
            .instance()
            .get(&DataKey::Schedule(schedule_id))
            .ok_or(VestingError::ScheduleNotFound)?;

        if caller != schedule.beneficiary && !Self::is_admin(&env, &caller) {
            return Err(VestingError::NotBeneficiaryOrAdmin);
        }
        if schedule.revoked {
            return Err(VestingError::ScheduleRevoked);
        }

        let old_beneficiary = schedule.beneficiary.clone();
        schedule.beneficiary = new_beneficiary.clone();

        env.storage()
            .instance()
            .set(&DataKey::Schedule(schedule_id), &schedule);

        let mut old_ben_schedules: Vec<u32> = env
            .storage()
            .instance()
            .get(&DataKey::BeneficiarySchedules(old_beneficiary.clone()))
            .unwrap_or(Vec::new(&env));
        let pos = old_ben_schedules.iter().position(|id| id == schedule_id);
        if let Some(idx) = pos {
            old_ben_schedules.remove(idx as u32);
        }
        env.storage()
            .instance()
            .set(&DataKey::BeneficiarySchedules(old_beneficiary.clone()), &old_ben_schedules);

        let mut new_ben_schedules: Vec<u32> = env
            .storage()
            .instance()
            .get(&DataKey::BeneficiarySchedules(new_beneficiary.clone()))
            .unwrap_or(Vec::new(&env));
        new_ben_schedules.push_back(schedule_id);
        env.storage()
            .instance()
            .set(&DataKey::BeneficiarySchedules(new_beneficiary.clone()), &new_ben_schedules);

        env.events().publish(
            (symbol_short!("benef"), symbol_short!("update")),
            (schedule_id, old_beneficiary.clone(), new_beneficiary.clone()),
        );

        Ok(())
    }

    pub fn get_schedule(env: &Env, schedule_id: u32) -> Result<VestingSchedule, VestingError> {
        env.storage()
            .instance()
            .get(&DataKey::Schedule(schedule_id))
            .ok_or(VestingError::ScheduleNotFound)
    }

    pub fn vested_amount(env: &Env, schedule_id: u32, timestamp: u64) -> Result<i128, VestingError> {
        let schedule = Self::get_schedule(env, schedule_id)?;
        Ok(Self::vested_amount_inner(&schedule, timestamp))
    }

    pub fn releasable_amount(env: &Env, schedule_id: u32) -> Result<i128, VestingError> {
        let schedule = Self::get_schedule(env, schedule_id)?;
        Self::releasable_amount_inner(&schedule, env)
    }

    pub fn beneficiary_schedules(env: &Env, beneficiary: Address) -> Vec<u32> {
        env.storage()
            .instance()
            .get(&DataKey::BeneficiarySchedules(beneficiary))
            .unwrap_or(Vec::new(env))
    }

    fn vested_amount_inner(schedule: &VestingSchedule, timestamp: u64) -> i128 {
        if timestamp < schedule.cliff {
            return 0;
        }

        let duration_end = schedule.start + schedule.duration;
        let vested_time = if timestamp > duration_end {
            duration_end
        } else {
            timestamp
        };

        let elapsed = vested_time - schedule.start;
        (schedule.total_amount * elapsed as i128) / schedule.duration as i128
    }

    fn releasable_amount_inner(schedule: &VestingSchedule, env: &Env) -> Result<i128, VestingError> {
        if schedule.revoked {
            return Ok(0);
        }

        let vested = Self::vested_amount_inner(schedule, env.ledger().timestamp());
        if vested <= schedule.released_amount {
            return Ok(0);
        }

        Ok(vested - schedule.released_amount)
    }
}

mod test;
