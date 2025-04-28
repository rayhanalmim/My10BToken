// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {PropertyManagement} from "./PropertyManagement.sol";

contract PropertyManagementView {
    PropertyManagement public propertyManagement;

    constructor(address _propertyManagement) {
        propertyManagement = PropertyManagement(_propertyManagement);
    }

    function getProperty(
        uint256 propertyId
    )
        external
        view
        returns (
            string memory name,
            uint256 totalSupply,
            uint256 totalRaised,
            uint256 annualRewardRate,
            uint256 investedAmount,
            address propertyToken,
            bool active
        )
    {
        (
            name,
            totalSupply,
            totalRaised,
            annualRewardRate,
            investedAmount,
            propertyToken,
            active
        ) = propertyManagement.properties(propertyId);
    }

    // Get full list of all property IDs
    function getAllProperties()
        external
        view
        returns (PropertyManagement.Property[] memory allProperties)
    {
        uint256 total = propertyManagement.propertyCounter();
        allProperties = new PropertyManagement.Property[](total);

        for (uint256 i = 0; i < total; i++) {
            (
                string memory name,
                uint256 totalSupply,
                uint256 totalRaised,
                uint256 annualRewardRate,
                uint256 investedAmount,
                address propertyToken,
                bool active
            ) = propertyManagement.properties(i + 1); // properties start from 1

            allProperties[i] = PropertyManagement.Property(
                name,
                totalSupply,
                totalRaised,
                annualRewardRate,
                investedAmount,
                propertyToken,
                active
            );
        }
    }

    // Get full investment info for a user across all properties
    function getUserInvestments(
        address user
    )
        external
        view
        returns (uint256[] memory propertyIds, uint256[] memory amounts)
    {
        uint256 totalProperties = propertyManagement.propertyCounter();
        uint256 count = 0;

        // First count how many properties the user invested in
        for (uint256 i = 1; i <= totalProperties; i++) {
            if (propertyManagement.userInvestments(user, i) > 0) {
                count++;
            }
        }

        propertyIds = new uint256[](count);
        amounts = new uint256[](count);

        uint256 index = 0;
        for (uint256 i = 1; i <= totalProperties; i++) {
            uint256 investedAmount = propertyManagement.userInvestments(
                user,
                i
            );
            if (investedAmount > 0) {
                propertyIds[index] = i;
                amounts[index] = investedAmount;
                index++;
            }
        }
    }

    // Get user's investment time (hold start times) across all properties
    function getUserHoldTimes(
        address user
    )
        external
        view
        returns (uint256[] memory propertyIds, uint256[] memory holdStartTimes)
    {
        uint256 totalProperties = propertyManagement.propertyCounter();
        uint256 count = 0;

        for (uint256 i = 1; i <= totalProperties; i++) {
            if (propertyManagement.userInvestments(user, i) > 0) {
                count++;
            }
        }

        propertyIds = new uint256[](count);
        holdStartTimes = new uint256[](count);

        uint256 index = 0;
        for (uint256 i = 1; i <= totalProperties; i++) {
            uint256 investedAmount = propertyManagement.userInvestments(
                user,
                i
            );
            if (investedAmount > 0) {
                propertyIds[index] = i;
                holdStartTimes[index] = propertyManagement.holdStartTime(
                    user,
                    i
                );
                index++;
            }
        }
    }

    // Get user's reward claim information across all properties
    function getUserRewards(
        address user
    )
        external
        view
        returns (
            uint256 accumulatedReward,
            uint256[] memory propertyIds,
            uint256[] memory lastClaimedTimes
        )
    {
        accumulatedReward = propertyManagement.accumulatedReward(user);
        uint256 totalProperties = propertyManagement.propertyCounter();
        uint256 count = 0;

        for (uint256 i = 1; i <= totalProperties; i++) {
            if (propertyManagement.userInvestments(user, i) > 0) {
                count++;
            }
        }

        propertyIds = new uint256[](count);
        lastClaimedTimes = new uint256[](count);

        uint256 index = 0;
        for (uint256 i = 1; i <= totalProperties; i++) {
            uint256 investedAmount = propertyManagement.userInvestments(
                user,
                i
            );
            if (investedAmount > 0) {
                propertyIds[index] = i;
                lastClaimedTimes[index] = propertyManagement.lastClaimed(
                    user,
                    i
                );
                index++;
            }
        }
    }

    function getFullUserInvestmentData(
        address user
    )
        external
        view
        returns (
            uint256[] memory propertyIds,
            uint256[] memory investments,
            uint256[] memory holdStartTimes,
            uint256[] memory lastClaimedTimes
        )
    {
        uint256 totalProperties = propertyManagement.propertyCounter();
        uint256 count = 0;

        // Step 1: Find how many properties user invested in
        for (uint256 i = 1; i <= totalProperties; i++) {
            if (propertyManagement.userInvestments(user, i) > 0) {
                count++;
            }
        }

        // Step 2: Initialize arrays
        propertyIds = new uint256[](count);
        investments = new uint256[](count);
        holdStartTimes = new uint256[](count);
        lastClaimedTimes = new uint256[](count);

        uint256 index = 0;
        for (uint256 i = 1; i <= totalProperties; i++) {
            uint256 invested = propertyManagement.userInvestments(user, i);
            if (invested > 0) {
                propertyIds[index] = i;
                investments[index] = invested;
                holdStartTimes[index] = propertyManagement.holdStartTime(
                    user,
                    i
                );
                lastClaimedTimes[index] = propertyManagement.lastClaimed(
                    user,
                    i
                );
                index++;
            }
        }
    }

    function getAllUserInvestmentData()
        external
        view
        returns (
            address[] memory users,
            uint256[][] memory propertyIds,
            uint256[][] memory investments,
            uint256[][] memory holdStartTimes
        )
    {
        uint256 totalUsers = propertyManagement.getInvestorCount();
        uint256 totalProperties = propertyManagement.propertyCounter();

        users = new address[](totalUsers);
        propertyIds = new uint256[][](totalUsers);
        investments = new uint256[][](totalUsers);
        holdStartTimes = new uint256[][](totalUsers);

        for (uint256 u = 0; u < totalUsers; u++) {
            address user = propertyManagement.investors(u);
            users[u] = user;

            // Count how many properties this user invested in
            uint256 propertyCount = 0;
            for (uint256 p = 1; p <= totalProperties; p++) {
                if (propertyManagement.userInvestments(user, p) > 0) {
                    propertyCount++;
                }
            }

            propertyIds[u] = new uint256[](propertyCount);
            investments[u] = new uint256[](propertyCount);
            holdStartTimes[u] = new uint256[](propertyCount);

            uint256 index = 0;
            for (uint256 p = 1; p <= totalProperties; p++) {
                uint256 invested = propertyManagement.userInvestments(user, p);
                if (invested > 0) {
                    propertyIds[u][index] = p;
                    investments[u][index] = invested;
                    holdStartTimes[u][index] = propertyManagement.holdStartTime(
                        user,
                        p
                    );
                    index++;
                }
            }
        }
    }
}
