// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {VestingContract} from "../src/VestingContract.sol";
import {MockERC20} from "../src/MockERC20.sol";
import {IVesting} from "../src/IVesting.sol";

contract VestingTest is Test {
    VestingContract public vesting;
    MockERC20 public token;

    address public admin = makeAddr("admin");
    address public beneficiary = makeAddr("beneficiary");
    address public other = makeAddr("other");

    uint256 constant TOTAL_SUPPLY = 1_000_000e18;
    uint256 constant ALLOCATION = 100_000e18;
    uint256 constant DURATION = 365 days;
    uint256 constant CLIFF = 90 days;

    function setUp() public {
        vm.startPrank(admin);
        token = new MockERC20("Test Token", "TST", TOTAL_SUPPLY);
        vesting = new VestingContract(address(token), admin);
        token.approve(address(vesting), type(uint256).max);
        vm.stopPrank();
    }

    function _createSchedule() internal returns (uint256) {
        vm.prank(admin);
        return vesting.createSchedule(beneficiary, ALLOCATION, block.timestamp, CLIFF, DURATION);
    }

    function _createScheduleAt(address beneficiary_, uint256 amount, uint256 start, uint256 cliff, uint256 duration)
        internal
        returns (uint256)
    {
        vm.prank(admin);
        return vesting.createSchedule(beneficiary_, amount, start, cliff, duration);
    }

    function test_Deployment() public view {
        assertEq(address(vesting.token()), address(token));
        assertEq(vesting.admin(), admin);
        assertEq(vesting.paused(), false);
        assertEq(vesting.scheduleCount(), 0);
    }

    function test_Deployment_RevertWhen_TokenZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert("VestingContract: token cannot be zero address");
        new VestingContract(address(0), admin);
    }

    function test_Deployment_RevertWhen_AdminZeroAddress() public {
        vm.expectRevert("VestingAdmin: admin cannot be zero address");
        new VestingContract(address(token), address(0));
    }

    function test_CreateSchedule() public {
        uint256 scheduleId = _createSchedule();
        assertEq(scheduleId, 0);
        assertEq(vesting.scheduleCount(), 1);

        IVesting.Schedule memory sched = vesting.getSchedule(scheduleId);
        assertEq(sched.beneficiary, beneficiary);
        assertEq(sched.totalAmount, ALLOCATION);
        assertEq(sched.releasedAmount, 0);
        assertEq(sched.cliff, block.timestamp + CLIFF);
        assertEq(sched.duration, DURATION);
        assertEq(sched.revoked, false);
    }

    function test_CreateSchedule_RevertWhen_NotAdmin() public {
        vm.prank(other);
        vm.expectRevert("VestingAdmin: caller is not admin");
        vesting.createSchedule(beneficiary, ALLOCATION, block.timestamp, CLIFF, DURATION);
    }

    function test_CreateSchedule_RevertWhen_ZeroBeneficiary() public {
        vm.prank(admin);
        vm.expectRevert("VestingContract: beneficiary cannot be zero address");
        vesting.createSchedule(address(0), ALLOCATION, block.timestamp, CLIFF, DURATION);
    }

    function test_CreateSchedule_RevertWhen_ZeroAmount() public {
        vm.prank(admin);
        vm.expectRevert("VestingContract: totalAmount must be greater than 0");
        vesting.createSchedule(beneficiary, 0, block.timestamp, CLIFF, DURATION);
    }

    function test_CreateSchedule_RevertWhen_ZeroDuration() public {
        vm.prank(admin);
        vm.expectRevert("VestingContract: duration must be greater than 0");
        vesting.createSchedule(beneficiary, ALLOCATION, block.timestamp, CLIFF, 0);
    }

    function test_CreateSchedule_RevertWhen_CliffExceedsDuration() public {
        vm.prank(admin);
        vm.expectRevert("VestingContract: cliff cannot exceed duration");
        vesting.createSchedule(beneficiary, ALLOCATION, block.timestamp, DURATION + 1, DURATION);
    }

    function test_CreateSchedule_RevertWhen_Paused() public {
        vm.prank(admin);
        vesting.pause();

        vm.prank(admin);
        vm.expectRevert("VestingAdmin: contract is paused");
        vesting.createSchedule(beneficiary, ALLOCATION, block.timestamp, CLIFF, DURATION);
    }

    function test_VestedAmount_BeforeCliff() public {
        uint256 scheduleId = _createSchedule();
        uint256 amount = vesting.vestedAmount(scheduleId, block.timestamp + CLIFF - 1);
        assertEq(amount, 0);
    }

    function test_VestedAmount_AtCliff() public {
        uint256 scheduleId = _createSchedule();
        skip(CLIFF);
        uint256 amount = vesting.vestedAmount(scheduleId, block.timestamp);
        assertEq(amount, (ALLOCATION * CLIFF) / DURATION);
    }

    function test_VestedAmount_Midpoint() public {
        uint256 scheduleId = _createSchedule();
        uint256 midPoint = CLIFF + (DURATION - CLIFF) / 2;
        skip(midPoint);
        uint256 amount = vesting.vestedAmount(scheduleId, block.timestamp);

        uint256 expected = (ALLOCATION * midPoint) / DURATION;
        assertEq(amount, expected);
    }

    function test_VestedAmount_FullyVested() public {
        uint256 scheduleId = _createSchedule();
        skip(DURATION);
        uint256 amount = vesting.vestedAmount(scheduleId, block.timestamp);
        assertEq(amount, ALLOCATION);
    }

    function test_VestedAmount_AfterFullVest() public {
        uint256 scheduleId = _createSchedule();
        skip(DURATION + 365 days);
        uint256 amount = vesting.vestedAmount(scheduleId, block.timestamp);
        assertEq(amount, ALLOCATION);
    }

    function test_VestedAmount_ZeroCliff() public {
        uint256 scheduleId = _createScheduleAt(beneficiary, ALLOCATION, block.timestamp, 0, DURATION);
        uint256 atStart = vesting.vestedAmount(scheduleId, block.timestamp);
        assertEq(atStart, 0);

        skip(1);
        uint256 afterOneSec = vesting.vestedAmount(scheduleId, block.timestamp);
        assertEq(afterOneSec, ALLOCATION / DURATION);
    }

    function test_Release_BeforeCliff() public {
        uint256 scheduleId = _createSchedule();
        vm.expectRevert("VestingContract: no tokens releasable");
        vesting.release(scheduleId);
    }

    function test_Release_AfterCliff() public {
        uint256 scheduleId = _createSchedule();
        skip(CLIFF + 30 days);

        uint256 releasable = vesting.releasableAmount(scheduleId);
        assertGt(releasable, 0);
        assertLt(releasable, ALLOCATION);

        uint256 balanceBefore = token.balanceOf(beneficiary);
        vm.prank(beneficiary);
        uint256 released = vesting.release(scheduleId);
        uint256 balanceAfter = token.balanceOf(beneficiary);

        assertEq(released, releasable);
        assertEq(balanceAfter - balanceBefore, released);

        IVesting.Schedule memory sched = vesting.getSchedule(scheduleId);
        assertEq(sched.releasedAmount, released);
    }

    function test_Release_Full() public {
        uint256 scheduleId = _createSchedule();
        skip(DURATION);

        vm.prank(beneficiary);
        uint256 released = vesting.release(scheduleId);
        assertEq(released, ALLOCATION);

        IVesting.Schedule memory sched = vesting.getSchedule(scheduleId);
        assertEq(sched.releasedAmount, ALLOCATION);
    }

    function test_Release_RevertWhen_AlreadyReleased() public {
        uint256 scheduleId = _createSchedule();
        skip(DURATION);
        vm.prank(beneficiary);
        vesting.release(scheduleId);

        vm.expectRevert("VestingContract: no tokens releasable");
        vm.prank(beneficiary);
        vesting.release(scheduleId);
    }

    function test_Release_RevertWhen_Paused() public {
        uint256 scheduleId = _createSchedule();
        skip(CLIFF + 1 days);

        vm.prank(admin);
        vesting.pause();

        vm.expectRevert("VestingAdmin: contract is paused");
        vesting.release(scheduleId);
    }

    function test_Release_MultipleBeneficiaries() public {
        address ben2 = makeAddr("ben2");
        uint256 amount2 = 50_000e18;

        _createScheduleAt(beneficiary, ALLOCATION, block.timestamp, CLIFF, DURATION);
        _createScheduleAt(ben2, amount2, block.timestamp, CLIFF, DURATION);

        skip(CLIFF + 30 days);

        vm.prank(beneficiary);
        uint256 r1 = vesting.release(0);

        vm.prank(ben2);
        uint256 r2 = vesting.release(1);

        assertGt(r1, 0);
        assertGt(r2, 0);
    }

    function test_Release_ByAnyone() public {
        uint256 scheduleId = _createSchedule();
        skip(CLIFF + 1 days);

        uint256 released = vesting.release(scheduleId);
        assertGt(released, 0);
    }

    function test_Revoke_BeforeCliff() public {
        uint256 scheduleId = _createSchedule();
        uint256 balanceBefore = token.balanceOf(admin);

        vm.prank(admin);
        vesting.revoke(scheduleId);

        uint256 balanceAfter = token.balanceOf(admin);
        assertEq(balanceAfter - balanceBefore, ALLOCATION);

        IVesting.Schedule memory sched = vesting.getSchedule(scheduleId);
        assertEq(sched.revoked, true);
    }

    function test_Revoke_AfterPartialRelease() public {
        uint256 scheduleId = _createSchedule();
        skip(CLIFF + 30 days);

        vm.prank(beneficiary);
        uint256 released = vesting.release(scheduleId);

        uint256 balanceBefore = token.balanceOf(admin);
        vm.prank(admin);
        vesting.revoke(scheduleId);
        uint256 balanceAfter = token.balanceOf(admin);

        assertEq(balanceAfter - balanceBefore, ALLOCATION - released);

        IVesting.Schedule memory sched = vesting.getSchedule(scheduleId);
        assertEq(sched.revoked, true);
    }

    function test_Revoke_RevertWhen_NotAdmin() public {
        uint256 scheduleId = _createSchedule();
        vm.prank(other);
        vm.expectRevert("VestingAdmin: caller is not admin");
        vesting.revoke(scheduleId);
    }

    function test_Revoke_RevertWhen_AlreadyRevoked() public {
        uint256 scheduleId = _createSchedule();
        vm.prank(admin);
        vesting.revoke(scheduleId);

        vm.prank(admin);
        vm.expectRevert("VestingContract: already revoked");
        vesting.revoke(scheduleId);
    }

    function test_Release_RevertWhen_Revoked() public {
        uint256 scheduleId = _createSchedule();
        vm.prank(admin);
        vesting.revoke(scheduleId);

        skip(CLIFF + 1 days);
        vm.expectRevert("VestingContract: no tokens releasable");
        vesting.release(scheduleId);
    }

    function test_UpdateBeneficiary() public {
        uint256 scheduleId = _createSchedule();
        address newBen = makeAddr("newBen");

        vm.prank(beneficiary);
        vesting.updateBeneficiary(scheduleId, newBen);

        IVesting.Schedule memory sched = vesting.getSchedule(scheduleId);
        assertEq(sched.beneficiary, newBen);
    }

    function test_UpdateBeneficiary_ByAdmin() public {
        uint256 scheduleId = _createSchedule();
        address newBen = makeAddr("newBen");

        vm.prank(admin);
        vesting.updateBeneficiary(scheduleId, newBen);

        IVesting.Schedule memory sched = vesting.getSchedule(scheduleId);
        assertEq(sched.beneficiary, newBen);
    }

    function test_UpdateBeneficiary_RevertWhen_NotAuthorized() public {
        uint256 scheduleId = _createSchedule();
        address newBen = makeAddr("newBen");

        vm.prank(other);
        vm.expectRevert("VestingContract: caller is not beneficiary or admin");
        vesting.updateBeneficiary(scheduleId, newBen);
    }

    function test_UpdateBeneficiary_RevertWhen_ZeroAddress() public {
        uint256 scheduleId = _createSchedule();

        vm.prank(beneficiary);
        vm.expectRevert("VestingContract: new beneficiary cannot be zero address");
        vesting.updateBeneficiary(scheduleId, address(0));
    }

    function test_UpdateBeneficiary_RevertWhen_Revoked() public {
        uint256 scheduleId = _createSchedule();

        vm.prank(admin);
        vesting.revoke(scheduleId);

        vm.prank(beneficiary);
        vm.expectRevert("VestingContract: schedule is revoked");
        vesting.updateBeneficiary(scheduleId, makeAddr("newBen"));
    }

    function test_Pause() public {
        vm.prank(admin);
        vesting.pause();
        assertEq(vesting.paused(), true);
    }

    function test_Pause_RevertWhen_NotAdmin() public {
        vm.prank(other);
        vm.expectRevert("VestingAdmin: caller is not admin");
        vesting.pause();
    }

    function test_Pause_RevertWhen_AlreadyPaused() public {
        vm.prank(admin);
        vesting.pause();

        vm.prank(admin);
        vm.expectRevert("VestingAdmin: contract is paused");
        vesting.pause();
    }

    function test_Unpause() public {
        vm.prank(admin);
        vesting.pause();

        vm.prank(admin);
        vesting.unpause();
        assertEq(vesting.paused(), false);
    }

    function test_Unpause_RevertWhen_NotAdmin() public {
        vm.prank(admin);
        vesting.pause();

        vm.prank(other);
        vm.expectRevert("VestingAdmin: caller is not admin");
        vesting.unpause();
    }

    function test_Unpause_RevertWhen_NotPaused() public {
        vm.prank(admin);
        vm.expectRevert("VestingAdmin: contract is not paused");
        vesting.unpause();
    }

    function test_TransferAdmin() public {
        address newAdmin = makeAddr("newAdmin");
        vm.prank(admin);
        vesting.transferAdmin(newAdmin);
        assertEq(vesting.admin(), newAdmin);
    }

    function test_TransferAdmin_RevertWhen_NotAdmin() public {
        vm.prank(other);
        vm.expectRevert("VestingAdmin: caller is not admin");
        vesting.transferAdmin(makeAddr("newAdmin"));
    }

    function test_TransferAdmin_RevertWhen_ZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert("VestingAdmin: new admin cannot be zero address");
        vesting.transferAdmin(address(0));
    }

    function test_NewAdminCanCreateSchedule() public {
        address newAdmin = makeAddr("newAdmin");
        vm.prank(admin);
        vesting.transferAdmin(newAdmin);

        vm.prank(admin);
        bool transferred = token.transfer(newAdmin, ALLOCATION);
        assertTrue(transferred);

        vm.startPrank(newAdmin);
        token.approve(address(vesting), ALLOCATION);
        uint256 scheduleId = vesting.createSchedule(beneficiary, ALLOCATION, block.timestamp, CLIFF, DURATION);
        vm.stopPrank();
        assertEq(scheduleId, 0);
    }

    function test_OldAdminCannotCreateScheduleAfterTransfer() public {
        address newAdmin = makeAddr("newAdmin");
        vm.prank(admin);
        vesting.transferAdmin(newAdmin);

        vm.prank(admin);
        vm.expectRevert("VestingAdmin: caller is not admin");
        vesting.createSchedule(beneficiary, ALLOCATION, block.timestamp, CLIFF, DURATION);
    }

    function test_MultipleSchedules() public {
        uint256 s1 = _createScheduleAt(beneficiary, ALLOCATION, block.timestamp, 0, DURATION);
        uint256 s2 = _createScheduleAt(beneficiary, ALLOCATION * 2, block.timestamp, 0, DURATION);
        uint256 s3 = _createScheduleAt(makeAddr("ben2"), ALLOCATION / 2, block.timestamp, 0, DURATION);

        assertEq(s1, 0);
        assertEq(s2, 1);
        assertEq(s3, 2);
        assertEq(vesting.scheduleCount(), 3);
    }

    function test_GetBeneficiarySchedules() public {
        _createScheduleAt(beneficiary, ALLOCATION, block.timestamp, 0, DURATION);
        _createScheduleAt(beneficiary, ALLOCATION, block.timestamp, 0, DURATION);
        _createScheduleAt(makeAddr("other"), ALLOCATION, block.timestamp, 0, DURATION);

        uint256[] memory schedules = vesting.getBeneficiarySchedules(beneficiary);
        assertEq(schedules.length, 2);
        assertEq(schedules[0], 0);
        assertEq(schedules[1], 1);

        assertEq(vesting.getBeneficiaryScheduleCount(beneficiary), 2);
        assertEq(vesting.getBeneficiaryScheduleCount(makeAddr("other")), 1);
    }

    function test_TotalAllocated() public {
        _createScheduleAt(beneficiary, ALLOCATION, block.timestamp, 0, DURATION);
        _createScheduleAt(beneficiary, ALLOCATION * 2, block.timestamp, 0, DURATION);

        assertEq(vesting.totalAllocated(), ALLOCATION * 3);
    }

    function test_ReleasableAmount_ZeroAfterRevoke() public {
        uint256 scheduleId = _createSchedule();
        skip(CLIFF + 1 days);

        vm.prank(admin);
        vesting.revoke(scheduleId);

        assertEq(vesting.releasableAmount(scheduleId), 0);
    }

    function testFuzz_VestingMath(uint256 elapsed, uint256 cliffOffset, uint256 duration) public {
        elapsed = bound(elapsed, 0, 10 * 365 days);
        cliffOffset = bound(cliffOffset, 0, elapsed > 0 ? elapsed - 1 : 0);
        duration = bound(duration, 1, 10 * 365 days);
        if (cliffOffset > duration) cliffOffset = duration;

        uint256 amount = bound(ALLOCATION, 1, type(uint128).max);

        uint256 start = block.timestamp;
        uint256 scheduleId = _createScheduleAt(beneficiary, amount, start, cliffOffset, duration);

        uint256 queryTime = start + elapsed;
        vm.warp(queryTime);

        uint256 vested = vesting.vestedAmount(scheduleId, queryTime);

        if (elapsed < cliffOffset) {
            assertEq(vested, 0);
        } else {
            uint256 cappedElapsed = elapsed > duration ? duration : elapsed;
            uint256 expected = (amount * cappedElapsed) / duration;
            assertEq(vested, expected, "vested amount mismatch");
        }
    }

    function testFuzz_CreateAndRelease(uint256 amount, uint256 releaseTime) public {
        amount = bound(amount, 1e18, 1_000_000e18);
        releaseTime = bound(releaseTime, CLIFF, DURATION);

        uint256 start = block.timestamp;
        _createScheduleAt(beneficiary, amount, start, CLIFF, DURATION);

        vm.warp(start + releaseTime);

        vm.prank(beneficiary);
        uint256 released = vesting.release(0);

        uint256 expected = (amount * releaseTime) / DURATION;
        assertEq(released, expected);

        IVesting.Schedule memory sched = vesting.getSchedule(0);
        assertEq(sched.releasedAmount, released);
    }

    function testFuzz_VestedAmountNeverExceedsTotal(uint256 elapsed1, uint256 elapsed2) public {
        elapsed1 = bound(elapsed1, 0, 10 * 365 days);
        elapsed2 = bound(elapsed2, 0, 10 * 365 days);

        uint256 scheduleId = _createScheduleAt(beneficiary, ALLOCATION, block.timestamp, CLIFF, DURATION);

        uint256 t1 = block.timestamp + elapsed1;
        uint256 t2 = block.timestamp + elapsed2;

        uint256 v1 = vesting.vestedAmount(scheduleId, t1);
        uint256 v2 = vesting.vestedAmount(scheduleId, t2);

        assertLe(v1, ALLOCATION);
        assertLe(v2, ALLOCATION);

        if (t2 >= t1) {
            assertGe(v2, v1);
        }
    }

    function test_Events_ScheduleCreated() public {
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit IVesting.ScheduleCreated(0, beneficiary, ALLOCATION, block.timestamp, block.timestamp + CLIFF, DURATION);
        vesting.createSchedule(beneficiary, ALLOCATION, block.timestamp, CLIFF, DURATION);
    }

    function test_Events_TokensReleased() public {
        uint256 scheduleId = _createSchedule();
        skip(CLIFF + 30 days);

        uint256 expected = vesting.releasableAmount(scheduleId);
        vm.expectEmit(true, true, true, true);
        emit IVesting.TokensReleased(scheduleId, beneficiary, expected);
        vesting.release(scheduleId);
    }

    function test_Events_ScheduleRevoked() public {
        uint256 scheduleId = _createSchedule();
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit IVesting.ScheduleRevoked(scheduleId, admin);
        vesting.revoke(scheduleId);
    }

    function test_Events_Paused() public {
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit IVesting.Paused(admin);
        vesting.pause();
    }

    function test_Events_Unpaused() public {
        vm.prank(admin);
        vesting.pause();

        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit IVesting.Unpaused(admin);
        vesting.unpause();
    }

    function test_Events_BeneficiaryUpdated() public {
        uint256 scheduleId = _createSchedule();
        address newBen = makeAddr("newBen");

        vm.prank(beneficiary);
        vm.expectEmit(true, true, true, true);
        emit IVesting.BeneficiaryUpdated(scheduleId, beneficiary, newBen);
        vesting.updateBeneficiary(scheduleId, newBen);
    }
}
