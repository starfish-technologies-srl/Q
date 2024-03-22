// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/metatx/ERC2771Context.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./QBuyAndBurn.sol";
import "./QERC20.sol";

contract Q is ERC2771Context, ReentrancyGuard {
    using SafeERC20 for QERC20;

    /**
     * Protocol fee percentage allocated to the miner.
     */
    uint256 public constant MINER_ALLOCATION = 70;

    /**
     * Protocol fee percentage allocated to the buy and burn of Q contract.
     */
    uint256 public constant QBUYBURN_ALLOCATION = 25;

    /**
     * Protocol fee percentage allocated for marketing/maintenance funds.
     */
    uint256 public constant MARKETING_MAINTENANCE_ALLOCATION = 2;

    /**
     * Protocol fee percentage allocated to the buy and burn of DXN contract.
     */
    uint256 public constant DXNBUYBURN_ALLOCATION = 1;

    /**
     * Used in combination with "cycleInteractions" to add a slight
     * penalization to subsequent cycle entries.
     */
    uint256 public constant LATE_BID = 1000;

    /**
     * Basis points representation of 100 percent.
     */
    uint256 public constant MAX_BPS = 100;

    /**
     * Used to minimise division remainder when earned fees are calculated.
     */
    uint256 public constant SCALING_FACTOR = 1e40;

    /**
     * Contract creation timestamp.
     * Initialized in constructor.
     */
    uint256 public immutable i_initialTimestamp;

    /**
     * Length of a reward distribution cycle. 
     * Initialized in contstructor to 1 day.
     */
    uint256 public immutable i_periodDuration;

    /**
     * Reward token amount allocated for the current cycle.
     */
    uint256 public currentCycleReward;

    /**
     * Helper variable to store pending stake amount.   
     */
    uint256 public pendingStake;

    /**
     * Index (0-based) of the current cycle.
     * 
     * Updated upon cycle setup that is triggered by contract interraction 
     * (account burn tokens, claims fees, claims rewards, stakes or unstakes).
     */
    uint256 public currentCycle;

    /**
     * Helper variable to store the index of the last active cycle.
     */
    uint256 public lastStartedCycle;

    /**
     * Stores the index of the penultimate active cycle plus one.
     */
    uint256 public previousStartedCycle;

    /**
     * Helper variable to store the index of the last active cycle.
     */
    uint256 public currentStartedCycle;

    /**
     * Stores the amount of stake that will be subracted from the total
     * stake once a new cycle starts.
     */
    uint256 public pendingStakeWithdrawal;

    /**
     * Diminisher of burned ether effectivness when calculating reward.
     */
    uint256 public currentBurnDecrease;

    /**
     * Registration fee for the current started cycle.
     */
    uint256 public currentRegistrationFee;

    /**
     * Number of times {enterCycle} has been called during current started cycle.
     */
    uint256 public cycleInteractions;

    /**
     * 2% of protocol fees are added to the marketing funds.
     */
    address public immutable marketingAddress;

    /**
     * 2% of protocol fees are added to the maintenance funds.
     */
    address public immutable maintenanceAddress;

    /**
     * 25% of protocol fees are sent to the buy and burn of Q contract.
     */
    address public immutable dxnBuyAndBurn;

    /**
     * 1% of protocol fees are sent to the buy and burn of DXN contract.
     */
    address public immutable qBuyAndBurn;

     /**
     * QBuyBurn contract instance
     * Initialized in constructor.
     */
    QBuyBurn public qBuyAndBurnInstance;

    /**
     * Q Reward Token contract.
     * Initialized in constructor.
     */
    QERC20 public qToken;
    
    /**
     * The amount of entries an account has during given cycle.
     * Resets during a new cycle when an account performs an action
     * that updates its stats.
     */
    mapping(address => uint256) public accCycleEntries;
    
    /**
     * The total amount of entries across all accounts per cycle.
     */
    mapping(uint256 => uint256) public cycleTotalEntries;

    /**
     * The last cycle in which an account has burned.
     */
    mapping(address => uint256) public lastActiveCycle;

    /**
     * Current unclaimed rewards and staked amounts per account.
     */
    mapping(address => uint256) public accRewards;

    /**
     * The fee amount the account can withdraw.
     */
    mapping(address => uint256) public accAccruedFees;

    /**
     * Total token rewards allocated per cycle.
     */
    mapping(uint256 => uint256) public rewardPerCycle;

    /**
     * Total unclaimed token reward and stake. 
     * 
     * Updated when a new cycle starts and when an account claims rewards, stakes or unstakes externally owned tokens.
     */
    mapping(uint256 => uint256) public summedCycleStakes;

    /**
     * The last cycle in which the account had its fees updated.
     */ 
    mapping(address => uint256) public lastFeeUpdateCycle;

    /**
     * The total amount of accrued fees per cycle.
     */
    mapping(uint256 => uint256) public cycleAccruedFees;

    /**
     * Sum of previous total cycle accrued fees divided by cycle stake.
     */
    mapping(uint256 => uint256) public cycleFeesPerStakeSummed;

    /**
     * Amount an account has staked and is locked during given cycle.
     */
    mapping(address => mapping(uint256 => uint256)) public accStakeCycle;

    /**
     * Stake amount an account can currently withdraw.
     */
    mapping(address => uint256) public accWithdrawableStake;

    /**
     * Cycle in which an account's stake is locked and begins generating fees.
     */
    mapping(address => uint256) public accFirstStake;

    /**
     * Same as accFirstStake, but stores the second stake seperately 
     * in case the account stakes in two consecutive active cycles.
     */
    mapping(address => uint256) public accSecondStake;

    /**
     * Returns whether an AI miner has registered or not.
     */
    mapping(address => bool) public isAIMinerRegistered;

    /**
     * Deposited ether balance for a given AI miner and cycle.
     */
    mapping(address => mapping(uint256 => uint256)) public aiMinerBalancePerCycle;

    /**
     * Lowest registered AI miner balance in a given cycle.
     */
    mapping(uint256 => uint256) public lowestCycleBalance;

    /**
     * Total amount of burned ether spent on {enterCycle} transactions.
     */

    mapping(uint256 => uint256) public nativeBurnedPerCycle;
    /**
     * @dev Emitted when `account` claims an amount of `fees` in native token
     * through {claimFees} in `cycle`.
     */
    event FeesClaimed(
        uint256 indexed cycle,
        address indexed account,
        uint256 fees
    );

    /**
     * @dev Emitted when `account` stakes `amount` Q tokens through
     * {stake} in `cycle`.
     */
    event Staked(
        uint256 indexed cycle,
        address indexed account,
        uint256 amount
    );

    /**
     * @dev Emitted when `account` unstakes `amount` Q tokens through
     * {unstake} in `cycle`.
     */
    event Unstaked(
        uint256 indexed cycle,
        address indexed account,
        uint256 amount
    );

    /**
     * @dev Emitted when `account` claims `amount` Q 
     * token rewards through {claimRewards} in `cycle`.
     */
    event RewardsClaimed(
        uint256 indexed cycle,
        address indexed account,
        uint256 reward
    );

    /**
     * @dev Emitted when calling {enterCycle} marking the new current `cycle`,
     * `calculatedCycleReward` and `summedCycleStakes`.
     */
    event NewCycleStarted(
        uint256 indexed cycle,
        uint256 summedCycleStakes
    );

    /**
     * @dev Emitted when calling {enterCycle} function for
     * `userAddress`  which burns `entryMultiplier` * 2500000 tokens
     */
    event Burn(
        address indexed userAddress,
        uint256 entryMultiplier
    );

    event NewAIRegistered(
        address indexed aiMiner,
        string name
    );

    /**
     * @dev Checks that the caller has sent an amount that is equal or greater 
     * than the sum of the protocol fee 
     * The change is sent back to the caller.
     * 
     */
    modifier gasWrapper() {
        uint256 startGas = gasleft();
        _;
        uint256 gasConsumed = startGas - gasleft();
        nativeBurnedPerCycle[currentCycle] += gasConsumed * block.basefee;
    }

    /**
     * @param forwarder forwarder contract address.
     */
    constructor(
        address forwarder,
        address _marketingAddress,
        address _maintenanceAddress,
        address _dxnBuyAndBurn,
        address[] memory AIRegisteredAddresses
    ) ERC2771Context(forwarder) payable {
        marketingAddress = _marketingAddress;
        maintenanceAddress = _maintenanceAddress;

        qToken = new QERC20();
        qBuyAndBurnInstance = new QBuyBurn(address(qToken));
        qBuyAndBurn = address(qBuyAndBurnInstance);

        dxnBuyAndBurn = _dxnBuyAndBurn;
        
        i_initialTimestamp = block.timestamp;
        i_periodDuration = 1 days;

        currentRegistrationFee = 10 ether;

        cycleAccruedFees[0] = msg.value;

        setAiMintersAddresses(AIRegisteredAddresses);
    }

    /**
     * Initializer function for marking as registered
     * those AI miners that have done so inside the 
     * Q payment contract. 
     */
    function setAiMintersAddresses(address[] memory AIAddresses) internal {
        uint256 numberOfAIs = AIAddresses.length;
        for(uint256 i=0; i < numberOfAIs; i++) {
            if(!isAIMinerRegistered[AIAddresses[i]]) {
                isAIMinerRegistered[AIAddresses[i]] = true;
            }
        }
    }

    /**
     * @param entryMultiplier multiplies the number of entries
     */
    function enterCycle(
        address aiMiner,
        uint256 entryMultiplier
    )
        external
        payable
        nonReentrant()
        gasWrapper()
    {
        require(entryMultiplier <= 100, "Q: max multiplier is 100");
        require(entryMultiplier > 0, "Q: min multiplier number is 1");

        require(isAIMinerRegistered[aiMiner], "Q:AI miner must be registered");

        calculateCycle();
        uint256 currentCycleMem = currentCycle;

        endCycle(currentCycleMem);
        setUpNewCycle(currentCycleMem);

        uint256 protocolFee = calculateProtocolFee(entryMultiplier);
        require(msg.value >= protocolFee , "Q: value less than protocol fee");

        updateStats(_msgSender(), currentCycleMem);
        updateStats(aiMiner, currentCycleMem);

        calculateCycleEntries(entryMultiplier, currentCycleMem, aiMiner);

        cycleAccruedFees[currentCycle] += protocolFee * MINER_ALLOCATION / MAX_BPS;

        lastActiveCycle[_msgSender()] = currentCycle;
        lastActiveCycle[aiMiner] = currentCycle;

        cycleInteractions++;

        distributeProtocolFee(protocolFee);

        if(msg.value > protocolFee) {
             sendViaCall(payable(msg.sender), msg.value - protocolFee);
        }
    }

    /**
     * Allows anyone to register as an AI miner if the
     * corresponding registration fee is paid.
     */
    function registerAIMiner(string calldata name) external payable {
        uint256 registrationFee = currentRegistrationFee;
        require(msg.value >= registrationFee);

        address aiMiner = _msgSender();
        require(!isAIMinerRegistered[aiMiner], "Q: AI miner already registered");

        isAIMinerRegistered[aiMiner] = true;

        if(msg.value > registrationFee) {
            sendViaCall(payable(msg.sender), msg.value - registrationFee);
        }

        cycleAccruedFees[currentStartedCycle] += currentRegistrationFee;
        emit NewAIRegistered(aiMiner, name);
    }

    /**
     * @dev Mints newly accrued account rewards and transfers the entire 
     * allocated amount to the transaction sender address.
     */
    function claimRewards(uint256 claimAmount)
        external
        nonReentrant()
    {
        calculateCycle();
        uint256 currentCycleMem = currentCycle;

        endCycle(currentCycleMem);
        updateStats(_msgSender(), currentCycleMem);

        uint256 reward = accRewards[_msgSender()] - accWithdrawableStake[_msgSender()];
        require(reward > 0, "Q: account has no rewards");
        require(claimAmount <= reward, "Q: claim amount exceeds rewards");

        accRewards[_msgSender()] -= claimAmount;
        if (lastStartedCycle == currentStartedCycle) {
            pendingStakeWithdrawal += claimAmount;
        } else {
            summedCycleStakes[currentCycleMem] = summedCycleStakes[currentCycleMem] - claimAmount;
        }

        qToken.mintReward(_msgSender(), claimAmount);
        emit RewardsClaimed(currentCycleMem, _msgSender(), claimAmount);
    }

    /**
     * @dev Transfers newly accrued fees to sender's address.
     */
    function claimFees(uint256 claimAmount)
        external
        nonReentrant()
    {
        calculateCycle();
        uint256 currentCycleMem = currentCycle;

        endCycle(currentCycleMem);
        updateStats(_msgSender(), currentCycleMem);

        uint256 fees = accAccruedFees[_msgSender()];
        require(fees > 0, "Q: amount is zero");
        require(claimAmount <= fees, "Q: claim amount exceeds fees");

        accAccruedFees[_msgSender()] = 0;

        sendViaCall(payable(_msgSender()), fees);
        
        emit FeesClaimed(getCurrentCycle(), _msgSender(), fees);
    }

    /**
     * @dev Stakes the given amount and increases the share of the daily allocated fees.
     * The tokens are transfered from sender account to this contract.
     * To receive the tokens back, the unstake function must be called by the same account address.
     * 
     * @param amount token amount to be staked (in wei).
     */
    function stake(uint256 amount)
        external
        nonReentrant()
    {
        calculateCycle();
        uint256 currentCycleMem = currentCycle;

        endCycle(currentCycleMem);
        updateStats(_msgSender(), currentCycleMem);

        require(amount > 0, "Q: amount is zero");
        require(currentCycleMem == currentStartedCycle, "Q: Only stake during active cycle");

        pendingStake += amount;

        uint256 cycleToSet = currentCycleMem + 1;
        if (lastStartedCycle == currentStartedCycle) {
            cycleToSet = lastStartedCycle + 1;
        }

        if (
            (cycleToSet != accFirstStake[_msgSender()] &&
                cycleToSet != accSecondStake[_msgSender()])
        ) {
            if (accFirstStake[_msgSender()] == 0) {
                accFirstStake[_msgSender()] = cycleToSet;
            } else if (accSecondStake[_msgSender()] == 0) {
                accSecondStake[_msgSender()] = cycleToSet;
            }
        }

        accStakeCycle[_msgSender()][cycleToSet] += amount;

        qToken.safeTransferFrom(_msgSender(), address(this), amount);
        emit Staked(cycleToSet, _msgSender(), amount);
    }

    /**
     * @dev Unstakes the given amount and decreases the share of the daily allocated fees.
     * If the balance is availabe, the tokens are transfered from this contract to the sender account.
     * 
     * @param amount token amount to be unstaked (in wei).
     */
    function unstake(uint256 amount)
        external
        nonReentrant()
    {
        calculateCycle();
        uint256 currentCycleMem = currentCycle;

        endCycle(currentCycleMem);
        updateStats(_msgSender(), currentCycleMem);
        
        require(amount > 0, "Q: amount is zero");
        require(
            amount <= accWithdrawableStake[_msgSender()],
            "Q: amount greater than withdrawable stake"
        );

        if (lastStartedCycle == currentStartedCycle) {
            pendingStakeWithdrawal += amount;
        } else {
            summedCycleStakes[currentCycleMem] -= amount;
        }

        accWithdrawableStake[_msgSender()] -= amount;
        accRewards[_msgSender()] -= amount;

        qToken.safeTransfer(_msgSender(), amount);
        emit Unstaked(currentCycleMem, _msgSender(), amount);
    }

    /**
     * @dev Returns the index of the cycle at the current block time.
     */
    function getCurrentCycle() public view returns (uint256) {
        return (block.timestamp - i_initialTimestamp) / i_periodDuration;
    }

    /**
     * Calculates the multiplier applied to a cycle entry
     * where "miner" is the designated AI miner.
     */
    function getAIMinerRankMultiplier(address miner) internal view returns(uint256 multiplier) {
        uint256 lastStartedCycleMem = lastStartedCycle;
        uint256 lastStartedCycleBalance = aiMinerBalancePerCycle[miner][lastStartedCycleMem];

        if(lastStartedCycleBalance != 0) {
            multiplier = lastStartedCycleBalance * 2 / lowestCycleBalance[lastStartedCycleMem];
        } else {
            multiplier = 1;
        }
    }

    /**
     * Calculates the protocol fee for entering the current cycle.
     */
    function calculateProtocolFee(uint256 entryMultiplier) internal view returns(uint256 protocolFee) {
        protocolFee = (0.01 ether * entryMultiplier * (LATE_BID  + cycleInteractions)) / LATE_BID;
    }

    /**
     * If the current registration fee is not 5 ether,
     * the fee gets updated for the new started cycle.
     */
    function calculateRegisterFee() internal {
        if(currentRegistrationFee > 5 ether) {
            uint256 newRegistrationFee = (currentRegistrationFee * 10000) / 10020;
            if(newRegistrationFee < 5 ether) {
                currentRegistrationFee = 5 ether;
            } else {
                currentRegistrationFee = newRegistrationFee;
            }
        }
    }

    /**
     * Based on the protocol fee, the corresponding allocations are
     * sent to each of the predefined addresses.
     */
    function distributeProtocolFee(uint256 protocolFee) internal {
        sendViaCall(payable(marketingAddress), protocolFee * MARKETING_MAINTENANCE_ALLOCATION / MAX_BPS);
        sendViaCall(payable(maintenanceAddress), protocolFee * MARKETING_MAINTENANCE_ALLOCATION / MAX_BPS);
        sendViaCall(payable(dxnBuyAndBurn), protocolFee * DXNBUYBURN_ALLOCATION / MAX_BPS);
        sendViaCall(payable(qBuyAndBurn), protocolFee * QBUYBURN_ALLOCATION / MAX_BPS);
    }

    /**
     * Increase the ether balance of a given AI miner - this action
     * counts towards ranking the AI miners and establishing
     * a multiplier when choosing a certain miner to enter the cycle with.
     */
    function addFundsForAIMiner(address aiMiner) external payable {
        uint256 cycle = currentStartedCycle;
        uint256 currentBalancePlusValue = aiMinerBalancePerCycle[aiMiner][cycle] + msg.value;

        require(currentBalancePlusValue >= 0.1 ether, "Q: Min. threshold balance not met");

        aiMinerBalancePerCycle[aiMiner][cycle] += msg.value;
                
        uint256 currentCycleLowestBalance = lowestCycleBalance[cycle];
        if(currentBalancePlusValue < currentCycleLowestBalance ||
            currentCycleLowestBalance == 0) {
            lowestCycleBalance[cycle] = currentBalancePlusValue;
        }
    }

    /**
     * Calculates entries to be added to the total of entries of the current cycle
     * and of the entrant.
     */
    function calculateCycleEntries(uint256 batchWeight, uint256 cycle, address aiMiner) internal {
        uint256 multiplier = getAIMinerRankMultiplier(aiMiner);
        if(multiplier > 1) {
            batchWeight *= multiplier;
        }

        cycleTotalEntries[cycle] += batchWeight * 100;
        accCycleEntries[_msgSender()] += batchWeight * 95;
        accCycleEntries[aiMiner] += batchWeight * 5;
    }

    /**
     * @dev Updates the index of the cycle.
     */
    function calculateCycle() internal {
        uint256 calculatedCycle = getCurrentCycle();
        
        if (calculatedCycle > currentCycle) {
            currentCycle = calculatedCycle;
        }
        
    }

    /**
     * @dev Updates the global helper variables related to fee distribution.
     */
    function endCycle(uint256 cycle) internal {
        if (cycle != currentStartedCycle) {
            previousStartedCycle = lastStartedCycle;
            lastStartedCycle = currentStartedCycle;
        }

        uint256 lastStartedCycleMem = lastStartedCycle;

        if (
            cycle > lastStartedCycleMem &&
            cycleFeesPerStakeSummed[lastStartedCycleMem + 1] == 0
        ) {
            calculateCycleReward(lastStartedCycleMem);
            
            uint256 feePerStake = (cycleAccruedFees[lastStartedCycleMem] * SCALING_FACTOR) / 
                summedCycleStakes[lastStartedCycleMem];
            
            cycleFeesPerStakeSummed[lastStartedCycleMem + 1] = cycleFeesPerStakeSummed[previousStartedCycle + 1] + feePerStake;
        }
    }

    /**
     * Calculates the Q reward amount to be distributed to
     * the entrants of the specified cycle. 
     */
    function calculateCycleReward(uint256 cycle) internal {  
        uint256 reward = nativeBurnedPerCycle[cycle] * 100 - 
            nativeBurnedPerCycle[cycle] * currentBurnDecrease / 200;

        currentCycleReward = reward;
        rewardPerCycle[cycle] = reward;

        summedCycleStakes[cycle] += currentCycleReward;
            
        if(currentBurnDecrease < 20000) {
            currentBurnDecrease++;
        }
    }

    /**
     * @dev Updates the global state related to starting a new cycle along 
     * with helper state variables used in computation of staking rewards.
     */
    function setUpNewCycle(uint256 cycle) internal {
        if (cycle != currentStartedCycle) {
            calculateRegisterFee();

            currentStartedCycle = cycle;

            cycleInteractions = 0;

            summedCycleStakes[currentStartedCycle] += summedCycleStakes[lastStartedCycle];
            
            if (pendingStake != 0) {
                summedCycleStakes[currentStartedCycle] += pendingStake;
                pendingStake = 0;
            }
            
            if (pendingStakeWithdrawal != 0) {
                summedCycleStakes[currentStartedCycle] -= pendingStakeWithdrawal;
                pendingStakeWithdrawal = 0;
            }
            
            emit NewCycleStarted(
                cycle,
                summedCycleStakes[currentStartedCycle]
            );
        }
    }

    /**
     * @dev Updates various helper state variables used to compute token rewards 
     * and fees distribution for a given account.
     * 
     * @param account the address of the account to make the updates for.
     */
    function updateStats(address account, uint256 cycle) internal {
         if (	
            cycle > lastActiveCycle[account] &&	
            accCycleEntries[account] != 0	
        ) {	
            uint256 lastCycleAccReward = ((accCycleEntries[account] * rewardPerCycle[lastActiveCycle[account]]) / 	
                cycleTotalEntries[lastActiveCycle[account]]);
            accRewards[account] += lastCycleAccReward;	
            accCycleEntries[account] = 0;
        }

        if (
            cycle > lastStartedCycle &&
            lastFeeUpdateCycle[account] != lastStartedCycle + 1
        ) {
            accAccruedFees[account] =
                accAccruedFees[account] +
                (
                    (accRewards[account] * 
                        (cycleFeesPerStakeSummed[lastStartedCycle + 1] - 
                            cycleFeesPerStakeSummed[lastFeeUpdateCycle[account]]
                        )
                    )
                ) /
                SCALING_FACTOR;
            lastFeeUpdateCycle[account] = lastStartedCycle + 1;
        }

        if (
            accFirstStake[account] != 0 &&
            cycle > accFirstStake[account]
        ) {
            uint256 unlockedFirstStake = accStakeCycle[account][accFirstStake[account]];

            accRewards[account] += unlockedFirstStake;
            accWithdrawableStake[account] += unlockedFirstStake;
            if (lastStartedCycle + 1 > accFirstStake[account]) {
                accAccruedFees[account] = accAccruedFees[account] + 
                (
                    (accStakeCycle[account][accFirstStake[account]] * 
                        (cycleFeesPerStakeSummed[lastStartedCycle + 1] - 
                            cycleFeesPerStakeSummed[accFirstStake[account]]
                        )
                    )
                ) / 
                SCALING_FACTOR;
            }

            accStakeCycle[account][accFirstStake[account]] = 0;
            accFirstStake[account] = 0;

            if (accSecondStake[account] != 0) {
                if (cycle > accSecondStake[account]) {
                    uint256 unlockedSecondStake = accStakeCycle[account][accSecondStake[account]];
                    accRewards[account] += unlockedSecondStake;
                    accWithdrawableStake[account] += unlockedSecondStake;
                    
                    if (lastStartedCycle + 1 > accSecondStake[account]) {
                        accAccruedFees[account] = accAccruedFees[account] + 
                        (
                            (accStakeCycle[account][accSecondStake[account]] * 
                                (cycleFeesPerStakeSummed[lastStartedCycle + 1] - 
                                    cycleFeesPerStakeSummed[accSecondStake[account]]
                                )
                            )
                        ) / 
                        SCALING_FACTOR;
                    }

                    accStakeCycle[account][accSecondStake[account]] = 0;
                    accSecondStake[account] = 0;
                } else {
                    accFirstStake[account] = accSecondStake[account];
                    accSecondStake[account] = 0;
                }
            }
        }
    }

    /**
     * Recommended method to use to send native coins.
     * 
     * @param to receiving address.
     * @param amount in wei.
     */
    function sendViaCall(address payable to, uint256 amount) internal {
        (bool sent, ) = to.call{value: amount}("");
        require(sent, "Q: failed to send amount");
    }

    receive() external payable {}

}