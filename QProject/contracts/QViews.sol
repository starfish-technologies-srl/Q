// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./Q.sol";

/**
 * Helper contract used to optimize dbxen state queries made by clients.
 */
contract QViews {

    /**
     * Main dbxen contract address to get the data from.
     */
    Q public qContract;

    /**
     * @param _dbXen DBXen.sol contract address
     */
    constructor(Q _dbXen) {
        qContract = _dbXen;
    }

    /**
     * @return main dbxen contract native coin balance
     */
    function deb0xContractBalance() external view returns (uint256) {
        return address(qContract).balance;
    }

    /**
     * @dev Withdrawable stake is the amount of qContract reward tokens that are currently 
     * 'unlocked' and can be unstaked by a given account.
     * 
     * @param staker the address to query the withdrawable stake for
     * @return the amount in wei
     */
    function getAccWithdrawableStake(address staker)
        external
        view
        returns (uint256)
    {
        uint256 calculatedCycle = qContract.getCurrentCycle();
        uint256 unlockedStake = 0;

        if (
            qContract.accFirstStake(staker) != 0 &&
            calculatedCycle > qContract.accFirstStake(staker)
        ) {
            unlockedStake += qContract.accStakeCycle(
                staker,
                qContract.accFirstStake(staker)
            );

            if (
                qContract.accSecondStake(staker) != 0 &&
                calculatedCycle > qContract.accSecondStake(staker)
            ) {
                unlockedStake += qContract.accStakeCycle(
                    staker,
                    qContract.accSecondStake(staker)
                );
            }
        }

        return qContract.accWithdrawableStake(staker) + unlockedStake;
    }

    /**
     * @dev Unclaimed fees represent the native coin amount that has been allocated 
     * to a given account but was not claimed yet.
     * 
     * @param account the address to query the unclaimed fees for
     * @return the amount in wei
     */
    function getUnclaimedFees(address account) external view returns (uint256) {
        uint256 calculatedCycle = qContract.getCurrentCycle();
        uint256 currentAccruedFees = qContract.accAccruedFees(account);
        uint256 currentCycleFeesPerStakeSummed;
        uint256 previousStartedCycleTemp = qContract.previousStartedCycle();
        uint256 lastStartedCycleTemp = qContract.lastStartedCycle();

        if (calculatedCycle != qContract.currentStartedCycle()) {
            previousStartedCycleTemp = lastStartedCycleTemp + 1;
            lastStartedCycleTemp = qContract.currentStartedCycle();
        }

        if (
            calculatedCycle > lastStartedCycleTemp &&
            qContract.cycleFeesPerStakeSummed(lastStartedCycleTemp + 1) == 0
        ) {
            uint256 feePerStake = 0;
            if(qContract.summedCycleStakes(lastStartedCycleTemp) != 0){
                feePerStake = ((qContract.cycleAccruedFees(
                lastStartedCycleTemp
            )) * qContract.SCALING_FACTOR()) /
                qContract.summedCycleStakes(lastStartedCycleTemp);
            }

            currentCycleFeesPerStakeSummed =
                qContract.cycleFeesPerStakeSummed(previousStartedCycleTemp) +
                feePerStake;
        } else {
            currentCycleFeesPerStakeSummed = qContract.cycleFeesPerStakeSummed(
                lastStartedCycleTemp + 1
            );
        }

        uint256 currentRewards = getUnclaimedRewards(account) + qContract.accWithdrawableStake(account);

        if (
            calculatedCycle > lastStartedCycleTemp &&
            qContract.lastFeeUpdateCycle(account) != lastStartedCycleTemp + 1
        ) {
            currentAccruedFees +=
                (
                    (currentRewards *
                        (currentCycleFeesPerStakeSummed -
                            qContract.cycleFeesPerStakeSummed(
                                qContract.lastFeeUpdateCycle(account)
                            )))
                ) /
                qContract.SCALING_FACTOR();
        }

        if (
            qContract.accFirstStake(account) != 0 &&
            calculatedCycle > qContract.accFirstStake(account) &&
            lastStartedCycleTemp + 1 > qContract.accFirstStake(account)
        ) {
            currentAccruedFees +=
                (
                    (qContract.accStakeCycle(account, qContract.accFirstStake(account)) *
                        (currentCycleFeesPerStakeSummed - qContract.cycleFeesPerStakeSummed(qContract.accFirstStake(account)
                            )))
                ) /
                qContract.SCALING_FACTOR();

            if (
                qContract.accSecondStake(account) != 0 &&
                calculatedCycle > qContract.accSecondStake(account) &&
                lastStartedCycleTemp + 1 > qContract.accSecondStake(account)
            ) {
                currentAccruedFees +=
                    (
                        (qContract.accStakeCycle(account, qContract.accSecondStake(account)
                        ) *
                            (currentCycleFeesPerStakeSummed -
                                qContract.cycleFeesPerStakeSummed(
                                    qContract.accSecondStake(account)
                                )))
                    ) /
                    qContract.SCALING_FACTOR();
            }
        }

        return currentAccruedFees;
    }

    /**
     * @return the reward token amount allocated for the current cycle
     */
    function calculateCycleReward() public view returns (uint256) {
        return (qContract.currentCycleReward() * 10000) / 10020;
    }

    /**
     * @dev Unclaimed rewards represent the amount of qContract reward tokens 
     * that were allocated but were not withdrawn by a given account.
     * 
     * @param account the address to query the unclaimed rewards for
     * @return the amount in wei
     */
    function getUnclaimedRewards(address account)
        public
        view
        returns (uint256)
    {
        uint256 currentRewards = qContract.accRewards(account) -  qContract.accWithdrawableStake(account);
        uint256 calculatedCycle = qContract.getCurrentCycle();

       if (
            calculatedCycle > qContract.lastActiveCycle(account) &&
            qContract.accCycleEntries(account) != 0
        ) {
            uint256 lastCycleAccReward = (qContract.accCycleEntries(account) *
                qContract.rewardPerCycle(qContract.lastActiveCycle(account))) /
                qContract.cycleTotalEntries(qContract.lastActiveCycle(account));

            currentRewards += lastCycleAccReward;
        }

        return currentRewards;
    }
}
