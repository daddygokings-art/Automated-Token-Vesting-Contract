// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "./interfaces/IERC20.sol";
import {IVesting} from "./IVesting.sol";
import {VestingAdmin} from "./VestingAdmin.sol";

contract VestingContract is VestingAdmin {
    using SafeMath for uint256;

    IERC20 public immutable token;
    uint256 public totalAllocated;
    uint256 public totalRevoked;

    Schedule[] private _schedules;
    mapping(uint256 => uint256) private _scheduleIndex;

    mapping(address => uint256[]) private _beneficiarySchedules;

    constructor(address _token, address _admin) VestingAdmin(_admin) {
        if (_token == address(0)) revert("VestingContract: token cannot be zero address");
        token = IERC20(_token);
    }

    function createSchedule(address beneficiary, uint256 totalAmount, uint256 start, uint256 cliff, uint256 duration)
        external
        onlyAdmin
        whenNotPaused
        returns (uint256 scheduleId)
    {
        if (beneficiary == address(0)) revert("VestingContract: beneficiary cannot be zero address");
        if (totalAmount == 0) revert("VestingContract: totalAmount must be greater than 0");
        if (duration == 0) revert("VestingContract: duration must be greater than 0");
        if (cliff > duration) revert("VestingContract: cliff cannot exceed duration");

        uint256 balanceBefore = token.balanceOf(address(this));
        bool transferredFrom = token.transferFrom(msg.sender, address(this), totalAmount);
        if (!transferredFrom) revert("VestingContract: transferFrom failed");
        uint256 balanceAfter = token.balanceOf(address(this));
        uint256 actualReceived = balanceAfter - balanceBefore;

        if (actualReceived < totalAmount) {
            revert("VestingContract: insufficient token transfer");
        }

        scheduleId = _schedules.length;
        _schedules.push(
            Schedule({
                beneficiary: beneficiary,
                revoker: admin,
                totalAmount: actualReceived,
                releasedAmount: 0,
                start: start,
                cliff: start + cliff,
                duration: duration,
                revoked: false
            })
        );

        _beneficiarySchedules[beneficiary].push(scheduleId);
        totalAllocated += actualReceived;

        emit ScheduleCreated(scheduleId, beneficiary, actualReceived, start, start + cliff, duration);
    }

    function release(uint256 scheduleId) external whenNotPaused returns (uint256 amount) {
        Schedule storage sched = _schedules[scheduleId];
        if (sched.beneficiary == address(0)) revert("VestingContract: schedule does not exist");

        amount = _releasableAmount(sched);
        if (amount == 0) revert("VestingContract: no tokens releasable");

        sched.releasedAmount += amount;
        bool transferred = token.transfer(sched.beneficiary, amount);
        if (!transferred) revert("VestingContract: transfer failed");

        emit TokensReleased(scheduleId, sched.beneficiary, amount);
    }

    function revoke(uint256 scheduleId) external onlyAdmin {
        Schedule storage sched = _schedules[scheduleId];
        if (sched.beneficiary == address(0)) revert("VestingContract: schedule does not exist");
        if (sched.revoked) revert("VestingContract: already revoked");

        sched.revoked = true;
        sched.revoker = msg.sender;

        uint256 unvested = _unvestedAmount(sched);
        totalRevoked += unvested;

        if (unvested > 0) {
            bool transferredRevoke = token.transfer(msg.sender, unvested);
            if (!transferredRevoke) revert("VestingContract: revoke transfer failed");
        }

        emit ScheduleRevoked(scheduleId, msg.sender);
    }

    function updateBeneficiary(uint256 scheduleId, address newBeneficiary) external {
        Schedule storage sched = _schedules[scheduleId];
        if (sched.beneficiary == address(0)) revert("VestingContract: schedule does not exist");
        if (msg.sender != sched.beneficiary && msg.sender != admin) {
            revert("VestingContract: caller is not beneficiary or admin");
        }
        if (newBeneficiary == address(0)) revert("VestingContract: new beneficiary cannot be zero address");
        if (sched.revoked) revert("VestingContract: schedule is revoked");

        address oldBeneficiary = sched.beneficiary;
        sched.beneficiary = newBeneficiary;

        emit BeneficiaryUpdated(scheduleId, oldBeneficiary, newBeneficiary);
    }

    function vestedAmount(uint256 scheduleId, uint256 timestamp) external view returns (uint256) {
        Schedule storage sched = _schedules[scheduleId];
        if (sched.beneficiary == address(0)) revert("VestingContract: schedule does not exist");
        return _vestedAmount(sched, timestamp);
    }

    function releasableAmount(uint256 scheduleId) external view returns (uint256) {
        Schedule storage sched = _schedules[scheduleId];
        if (sched.beneficiary == address(0)) revert("VestingContract: schedule does not exist");
        return _releasableAmount(sched);
    }

    function getSchedule(uint256 scheduleId) external view returns (Schedule memory) {
        if (scheduleId >= _schedules.length) revert("VestingContract: schedule does not exist");
        return _schedules[scheduleId];
    }

    function scheduleCount() external view returns (uint256) {
        return _schedules.length;
    }

    function getBeneficiarySchedules(address beneficiary) external view returns (uint256[] memory) {
        return _beneficiarySchedules[beneficiary];
    }

    function getBeneficiaryScheduleCount(address beneficiary) external view returns (uint256) {
        return _beneficiarySchedules[beneficiary].length;
    }

    function _vestedAmount(Schedule storage sched, uint256 timestamp) private view returns (uint256) {
        if (timestamp < sched.cliff) {
            return 0;
        }

        uint256 durationEnd = sched.start + sched.duration;
        uint256 vestedTime = timestamp > durationEnd ? durationEnd : timestamp;

        uint256 elapsed = vestedTime - sched.start;

        return (sched.totalAmount * elapsed) / sched.duration;
    }

    function _releasableAmount(Schedule storage sched) private view returns (uint256) {
        if (sched.revoked) return 0;

        uint256 vested = _vestedAmount(sched, block.timestamp);
        if (vested <= sched.releasedAmount) return 0;

        return vested - sched.releasedAmount;
    }

    function _unvestedAmount(Schedule storage sched) private view returns (uint256) {
        if (sched.totalAmount <= sched.releasedAmount) return 0;

        return sched.totalAmount - sched.releasedAmount;
    }
}

library SafeMath {
    function tryAdd(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            uint256 c = a + b;
            if (c < a) return (false, 0);
            return (true, c);
        }
    }

    function trySub(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            if (b > a) return (false, 0);
            return (true, a - b);
        }
    }

    function tryMul(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            if (a == 0) return (true, 0);
            uint256 c = a * b;
            if (c / a != b) return (false, 0);
            return (true, c);
        }
    }

    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        return a + b;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return a - b;
    }

    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        return a * b;
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return a / b;
    }
}
