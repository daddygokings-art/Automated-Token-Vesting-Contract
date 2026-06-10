// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IVesting {
    struct Schedule {
        address beneficiary;
        address revoker;
        uint256 totalAmount;
        uint256 releasedAmount;
        uint256 start;
        uint256 cliff;
        uint256 duration;
        bool revoked;
    }

    event ScheduleCreated(
        uint256 indexed scheduleId,
        address indexed beneficiary,
        uint256 totalAmount,
        uint256 start,
        uint256 cliff,
        uint256 duration
    );
    event TokensReleased(uint256 indexed scheduleId, address indexed beneficiary, uint256 amount);
    event ScheduleRevoked(uint256 indexed scheduleId, address indexed revoker);
    event BeneficiaryUpdated(
        uint256 indexed scheduleId, address indexed oldBeneficiary, address indexed newBeneficiary
    );
    event Paused(address account);
    event Unpaused(address account);

    function createSchedule(address beneficiary, uint256 totalAmount, uint256 start, uint256 cliff, uint256 duration)
        external
        returns (uint256 scheduleId);
    function release(uint256 scheduleId) external returns (uint256 amount);
    function revoke(uint256 scheduleId) external;
    function vestedAmount(uint256 scheduleId, uint256 timestamp) external view returns (uint256);
    function releasableAmount(uint256 scheduleId) external view returns (uint256);
    function updateBeneficiary(uint256 scheduleId, address newBeneficiary) external;
    function pause() external;
    function unpause() external;
    function getSchedule(uint256 scheduleId) external view returns (Schedule memory);
    function scheduleCount() external view returns (uint256);
}
