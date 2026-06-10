// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IVesting} from "./IVesting.sol";

abstract contract VestingAdmin is IVesting {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    address public admin;
    bool public paused;

    modifier onlyAdmin() {
        if (msg.sender != admin) {
            revert("VestingAdmin: caller is not admin");
        }
        _;
    }

    modifier whenNotPaused() {
        if (paused) {
            revert("VestingAdmin: contract is paused");
        }
        _;
    }

    modifier whenPaused() {
        if (!paused) {
            revert("VestingAdmin: contract is not paused");
        }
        _;
    }

    constructor(address _admin) {
        if (_admin == address(0)) {
            revert("VestingAdmin: admin cannot be zero address");
        }
        admin = _admin;
    }

    function transferAdmin(address newAdmin) external onlyAdmin {
        if (newAdmin == address(0)) {
            revert("VestingAdmin: new admin cannot be zero address");
        }
        admin = newAdmin;
    }

    function pause() external onlyAdmin whenNotPaused {
        paused = true;
        emit Paused(msg.sender);
    }

    function unpause() external onlyAdmin whenPaused {
        paused = false;
        emit Unpaused(msg.sender);
    }
}
