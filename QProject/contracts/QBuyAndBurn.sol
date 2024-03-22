// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.22;

import "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";
import "@uniswap/v3-periphery/contracts/libraries/PoolAddress.sol";
import "./interfaces/IWETH9Minimal.sol";
import "./interfaces/ISwapRouterMinimal.sol";

contract QBuyBurn {

    uint256 public i_initialTimestamp;

    uint256 public i_periodDuration;

    uint256 public firstCycleReceivedEther;

    uint256 public globalCountForDays;

    uint256 public collectedAmount;

    address public Q; 
    
    address public immutable Q_WETH9_Pool;    

    address public constant UNISWAP_V3_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;

    address public constant WETH9 = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270; 

    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    address public constant SWAP_ROUTER = 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;

    mapping(uint256 => bool) public feeAlreadyDistributed;

    uint24 public constant poolFee = 10000;

    receive() external payable {
        if(block.timestamp < i_initialTimestamp + 1 days) {
            firstCycleReceivedEther += msg.value;
         } else {
            collectedAmount += msg.value;
         }
    }

    constructor(address _qAddress) {
        i_initialTimestamp = block.timestamp;
        i_periodDuration = 1 days;
        Q_WETH9_Pool = computePoolAddress(WETH9, _qAddress, poolFee);
        Q = _qAddress;
    }

    function burnToken(uint256 amountToBurn) public {
        require(isContract(Q_WETH9_Pool), "BuyAndBurn: The pool is not yet created!");
        require(block.timestamp > i_initialTimestamp + 1 days,"BuyAndBurn: You cannot burn in first day!");
        require(amountToBurn >= 0.1 ether, "BuyAndBurn: Inufficient funds for burn!");
        uint256 theFiftiethPart = (firstCycleReceivedEther / 50);
        uint256 amountToCompare = collectedAmount;
        if(globalCountForDays < 50) 
            amountToCompare = collectedAmount + theFiftiethPart;
        require(amountToCompare >= amountToBurn, "BuyAndBurn: The contribution is lower than the entered amount!");
        uint256 currentCycle = getCurrentCycle();
        collectedAmount -= amountToBurn;
        uint256 amountETH;
        uint256 callerPercent;
        if(globalCountForDays < 50 && !feeAlreadyDistributed[currentCycle]) {
            uint256 amount = amountToBurn + theFiftiethPart;
            amountETH = amount * 99 / 100;
            callerPercent = amount / 100;
            globalCountForDays ++;
            feeAlreadyDistributed[currentCycle] = true;
        } else {
            amountETH = amountToBurn * 99 / 100;
            callerPercent = amountToBurn / 100;
        }

        uint256 amountOutExpected = _getQuote(uint128(amountETH));
        uint256 minTokenAmount = (amountOutExpected * 90) / 100;
        require(minTokenAmount > 0, "Min. token amount can't be zero");

        _swap(minTokenAmount, amountETH);

        (bool success,) = payable(msg.sender).call{value: callerPercent}("");
        require(success, "Transfer failed.");
    }

    function _swap(uint256 amountOutMinimum, uint256 amountIn) private {
        ISwapRouterMinimal.ExactInputSingleParams memory params =
            ISwapRouterMinimal.ExactInputSingleParams({
                tokenIn: WETH9,
                tokenOut: Q,
                fee: poolFee,
                recipient: BURN_ADDRESS,
                amountIn: amountIn,
                amountOutMinimum: amountOutMinimum,
                sqrtPriceLimitX96: 0
            });

        ISwapRouterMinimal(SWAP_ROUTER).exactInputSingle{value: amountIn}(params);
    }

    function _getQuote(uint128 amountIn) public view returns(uint256 amountOut) {
        (int24 tick, ) = OracleLibrary.consult(Q_WETH9_Pool, 1);
        amountOut = OracleLibrary.getQuoteAtTick(tick, amountIn, WETH9, Q);
    }

    function isContract(address _addr) private returns (bool isContract) {
        uint32 size;
        assembly {
            size := extcodesize(_addr)
        }
        return (size > 0);
    }

    function computePoolAddress(address tokenA, address tokenB, uint24 fee) public view returns (address pool) {
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        PoolAddress.PoolKey memory key = PoolAddress.PoolKey({token0: token0, token1: token1, fee: fee});
        pool = PoolAddress.computeAddress(UNISWAP_V3_FACTORY, key);
        return pool;
    }   

    function getCurrentCycle() public view returns (uint256) {
        return (block.timestamp - i_initialTimestamp) / i_periodDuration;
    }
}