// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/metatx/ERC2771Context.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./QERC20.sol";

contract Q is ERC2771Context, ReentrancyGuard {
    using SafeERC20 for QERC20;

    address public marketingAddress;

    address public maintenanceAddress;

    address public dxnBuyAndBurn;

    address public qBuyAndBurn;
    /**
     * Q Reward Token contract.
     * Initialized in constructor.
     */
    QERC20 public qToken;

    uint256 public constant MINER_ALLOCATION = 70;

    uint256 public constant QBUYBURN_ALLOCATION = 25;

    uint256 public constant MARKETING_ALLOCATION = 2;

    uint256 public constant MAINTENANCE_ALLOCATION = 2;

    uint256 public constant DXNBUYBURN_ALLOCATION = 1;

    uint256 public constant BURN_DIMINISHER = 10020;

    uint256 public constant LATE_BID = 1001;

    uint256 public constant LATE_BID_MAX = 1000;

    /**
     * Basis points representation of 100 percent.
     */
    uint256 public constant MAX_BPS = 100;

    /**
     * Basis points representation of 100 percent.
     */
    uint256 public constant MAX_BPS_101 = 101;

    /**
     * Amount of XEN tokens per batch
     */
    uint256 public constant XEN_BATCH_AMOUNT = 2_500_000 ether;

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
     * Reward token amount allocated for the previous cycle.
     */
    uint256 public lastCycleReward;

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
     * Accumulates fees while there are no tokens staked after the
     * entire token supply has been distributed. Once tokens are
     * staked again, these fees will be distributed in the next
     * active cycle.
     */
    uint256 public pendingFees;

    uint256 public currentBurnDecrease;

    uint256 public currentRegistrationFee;
    /**
     * The amount of batches an account has burned.
     * Resets during a new cycle when an account performs an action
     * that updates its stats.
     */
    mapping(address => uint256) public accCycleBatchesBurned;
    
    /**
     * The total amount of batches all accounts have burned per cycle.
     */
    mapping(uint256 => uint256) public cycleTotalBatchesBurned;

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

    mapping(uint256 => uint256) public cycleInteraction;

    mapping(address => bool) public isAIMinerRegistered;

    mapping(address => mapping(uint256 => uint256)) public aiMinerBalancePerCycle;

    mapping(uint256 => uint256) public totalAIMinerBalancesPerCycle;

    mapping(uint256 => uint256) public lowestCycleBalance;

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
     * @dev Emitted when `account` stakes `amount` DBX tokens through
     * {stake} in `cycle`.
     */
    event Staked(
        uint256 indexed cycle,
        address indexed account,
        uint256 amount
    );

    /**
     * @dev Emitted when `account` unstakes `amount` DBX tokens through
     * {unstake} in `cycle`.
     */
    event Unstaked(
        uint256 indexed cycle,
        address indexed account,
        uint256 amount
    );

    /**
     * @dev Emitted when `account` claims `amount` DBX 
     * token rewards through {claimRewards} in `cycle`.
     */
    event RewardsClaimed(
        uint256 indexed cycle,
        address indexed account,
        uint256 reward
    );

    /**
     * @dev Emitted when calling {burnBatch} marking the new current `cycle`,
     * `calculatedCycleReward` and `summedCycleStakes`.
     */
    event NewCycleStarted(
        uint256 indexed cycle,
        uint256 calculatedCycleReward,
        uint256 summedCycleStakes
    );

    /**
     * @dev Emitted when calling {burnBatch} function for
     * `userAddress`  which burns `batchNumber` * 2500000 tokens
     */
    event Burn(
        address indexed userAddress,
        uint256 batchNumber
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
        dxnBuyAndBurn = _dxnBuyAndBurn;
        maintenanceAddress = _maintenanceAddress;
        qToken = new QERC20();
        i_initialTimestamp = block.timestamp;
        i_periodDuration = 5 minutes;
        currentCycleReward = 10000 * 1e18;
        summedCycleStakes[0] = 10000 * 1e18;
        rewardPerCycle[0] = 10000 * 1e18;
        currentRegistrationFee = 10 * 1e18;
        setAiMintersAddresses(AIRegisteredAddresses);
    }

    function setAiMintersAddresses(address[] memory AIAddresses) internal {
        uint256 numberOfAIs = AIAddresses.length;
        for(uint256 i=0; i < numberOfAIs; i++) {
            if(!isAIMinerRegistered[AIAddresses[i]]) {
                isAIMinerRegistered[AIAddresses[i]] = true;
            }
        }
    }

    /**
     * @dev Burn batchNumber * 2.500.000 tokens 
     * 
     * @param batchNumber number of batches
     */
    function burnBatch(
        address aiMiner,
        uint256 batchNumber
    )
        external
        payable
        nonReentrant()
        gasWrapper()
    {
        require(batchNumber <= 100, "DBXen: maxim batch number is 100");
        require(batchNumber > 0, "DBXen: min batch number is 1");

        calculateCycle();
        uint256 currentCycleMem = currentCycle;

        uint256 protocolFee = calculateProtocolFee(batchNumber, currentCycleMem);
        require(msg.value >= protocolFee , "DBXen: value less than protocol fee");

        updateCycleFeesPerStakeSummed(currentCycleMem);
        setUpNewCycle(currentCycleMem);
        updateStats(_msgSender(), currentCycleMem);
        updateStats(aiMiner, currentCycleMem);

        calculateCycleEntries(batchNumber, currentCycleMem, aiMiner);

        registerPaymentContractBalance(aiMiner, currentCycleMem);

        cycleAccruedFees[currentCycle] += protocolFee * MINER_ALLOCATION / MAX_BPS;

        lastActiveCycle[_msgSender()] = currentCycle;
        lastActiveCycle[aiMiner] = currentCycle;

        cycleInteraction[currentCycle]++;

        distributeProtocolFee(protocolFee);

        if(msg.value > protocolFee) {
             sendViaCall(payable(msg.sender), msg.value - protocolFee);
        }
    }

    function registerAIMiner(string calldata name) external payable {
        address aiMiner = msg.sender;
        require(msg.value >= currentRegistrationFee);
        require(!isAIMinerRegistered[aiMiner], "Q: AI miner already registered");
        isAIMinerRegistered[aiMiner] = true;
        if(msg.value > currentRegistrationFee) {
            sendViaCall(payable(_msgSender()), msg.value - currentRegistrationFee);
        }

        cycleAccruedFees[currentStartedCycle] += currentRegistrationFee;
        emit NewAIRegistered(aiMiner, name);
    }

    function addFundsForAIMiner(address aiMiner) external payable {
        registerPaymentContractBalance(aiMiner, currentStartedCycle);
    }

    /**
     * @dev Mints newly accrued account rewards and transfers the entire 
     * allocated amount to the transaction sender address.
     */
    function claimRewards()
        external
        nonReentrant()
    {
        calculateCycle();
        uint256 currentCycleMem = currentCycle;

        updateCycleFeesPerStakeSummed(currentCycleMem);
        updateStats(_msgSender(), currentCycleMem);
        uint256 reward = accRewards[_msgSender()] - accWithdrawableStake[_msgSender()];
        
        require(reward > 0, "DBXen: account has no rewards");

        accRewards[_msgSender()] -= reward;
        if (lastStartedCycle == currentStartedCycle) {
            pendingStakeWithdrawal += reward;
        } else {
            summedCycleStakes[currentCycleMem] = summedCycleStakes[currentCycleMem] - reward;
        }

        qToken.mintReward(_msgSender(), reward);
        emit RewardsClaimed(currentCycleMem, _msgSender(), reward);
    }

    /**
     * @dev Transfers newly accrued fees to sender's address.
     */
    function claimFees()
        external
        nonReentrant()
    {
        calculateCycle();
        uint256 currentCycleMem = currentCycle;

        updateCycleFeesPerStakeSummed(currentCycleMem);
        updateStats(_msgSender(), currentCycleMem);

        uint256 fees = accAccruedFees[_msgSender()];
        require(fees > 0, "DBXen: amount is zero");
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

        updateCycleFeesPerStakeSummed(currentCycleMem);
        updateStats(_msgSender(), currentCycleMem);
        require(amount > 0, "DBXen: amount is zero");
        require(currentCycleMem == currentStartedCycle, "DBXeNFT: Only stake during active cycle");
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

        updateCycleFeesPerStakeSummed(currentCycleMem);
        updateStats(_msgSender(), currentCycleMem);
        require(amount > 0, "DBXen: amount is zero");

        require(
            amount <= accWithdrawableStake[_msgSender()],
            "DBXen: amount greater than withdrawable stake"
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

    function getAIMinerRankMultiplier(address miner) internal view returns(uint256 multiplier) {
        uint256 lastStartedCycleMem = lastStartedCycle;
        uint256 lastStartedCycleBalance = 
            aiMinerBalancePerCycle[miner][lastStartedCycleMem];
        if
        (
            lastStartedCycleBalance == 0 ||
            !isAIMinerRegistered[miner] || 
            lastStartedCycleMem == 0
        ) {
            multiplier = 1;
        } else {
            multiplier = lastStartedCycleBalance * 2 / lowestCycleBalance[lastStartedCycleMem];
        }
    }

    function calculateProtocolFee(uint256 batchNumber, uint256 cycle) internal view returns(uint256 protocolFee) {
        protocolFee = (0.01 ether * batchNumber * 
            (LATE_BID  + cycleInteraction[cycle])) / LATE_BID_MAX;
    }

    function calculateRegisterFee() internal {
        if(currentRegistrationFee != 5 ether) {
            uint256 newRegistrationFee = (currentRegistrationFee * 10000) / 10020;
            if(newRegistrationFee < 5 ether) {
                currentRegistrationFee = 5 ether;
            } else {
                currentRegistrationFee = newRegistrationFee;
            }
        }
    }

    function distributeProtocolFee(uint256 protocolFee) internal {
        sendViaCall(payable(marketingAddress), protocolFee * MARKETING_ALLOCATION / MAX_BPS);
        sendViaCall(payable(maintenanceAddress), protocolFee * MAINTENANCE_ALLOCATION / MAX_BPS);
        sendViaCall(payable(dxnBuyAndBurn), protocolFee * DXNBUYBURN_ALLOCATION / MAX_BPS);
        sendViaCall(payable(qBuyAndBurn), protocolFee * QBUYBURN_ALLOCATION / MAX_BPS);
    }

    function registerPaymentContractBalance(address aiMiner, uint256 cycle) internal {
        uint256 currentBalancePlusValue = aiMinerBalancePerCycle[aiMiner][cycle] + msg.value;
        require(currentBalancePlusValue >= 0.1 ether, "Q: Min. threshold balance not met");

        totalAIMinerBalancesPerCycle[cycle] += msg.value;
        aiMinerBalancePerCycle[aiMiner][cycle] += msg.value;
                
        uint256 currentCycleLowestBalance = lowestCycleBalance[cycle];
        if(currentBalancePlusValue < currentCycleLowestBalance ||
            currentCycleLowestBalance == 0) {
            lowestCycleBalance[cycle] = currentBalancePlusValue;
        }
    }

    function calculateCycleEntries(uint256 batchWeight, uint256 cycle, address aiMiner) internal {
        uint256 multiplier = getAIMinerRankMultiplier(aiMiner);
        if(multiplier > 1) {
            batchWeight *= multiplier;
        }

        cycleTotalBatchesBurned[cycle] += batchWeight * 100;
        accCycleBatchesBurned[_msgSender()] += batchWeight * 95;
        accCycleBatchesBurned[aiMiner] += batchWeight * 5;
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
    function updateCycleFeesPerStakeSummed(uint256 cycle) internal {
        if (cycle != currentStartedCycle) {
            previousStartedCycle = lastStartedCycle + 1;
            lastStartedCycle = currentStartedCycle;
        }
       
        if (
            cycle > lastStartedCycle &&
            cycleFeesPerStakeSummed[lastStartedCycle + 1] == 0
        ) {
            uint256 feePerStake;
            if(summedCycleStakes[lastStartedCycle] != 0) {
                feePerStake = ((cycleAccruedFees[lastStartedCycle] + pendingFees) * SCALING_FACTOR) / 
            summedCycleStakes[lastStartedCycle];
                pendingFees = 0;
            } else {
                pendingFees += cycleAccruedFees[lastStartedCycle];
                feePerStake = 0;
            }
            
            cycleFeesPerStakeSummed[lastStartedCycle + 1] = cycleFeesPerStakeSummed[previousStartedCycle] + feePerStake;
        }
    }

    function calculateCycleReward(uint256 cycle) internal returns (uint256 reward) {  
        reward = nativeBurnedPerCycle[cycle] * 100 - 
            nativeBurnedPerCycle[cycle] * currentBurnDecrease / 200;
            
        if(currentBurnDecrease < 20000) {
            currentBurnDecrease++;
        }
    }

    /**
     * @dev Updates the global state related to starting a new cycle along 
     * with helper state variables used in computation of staking rewards.
     */
    function setUpNewCycle(uint256 cycle) internal {
        if (rewardPerCycle[cycle] == 0) {
            // lastCycleReward = currentCycleReward;
            calculateRegisterFee();
            uint256 calculatedCycleReward = calculateCycleReward(lastStartedCycle);
            currentCycleReward = calculatedCycleReward;
            rewardPerCycle[cycle] = calculatedCycleReward;

            currentStartedCycle = cycle;
            
            summedCycleStakes[currentStartedCycle] += summedCycleStakes[lastStartedCycle] + currentCycleReward;
            
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
                calculatedCycleReward,
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
            accCycleBatchesBurned[account] != 0	
        ) {	
            uint256 lastCycleAccReward = ((accCycleBatchesBurned[account] * rewardPerCycle[lastActiveCycle[account]]) / 	
                cycleTotalBatchesBurned[lastActiveCycle[account]]);
            accRewards[account] += lastCycleAccReward;	
            accCycleBatchesBurned[account] = 0;
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
        require(sent, "DBXen: failed to send amount");
    }

    receive() external payable {}

}