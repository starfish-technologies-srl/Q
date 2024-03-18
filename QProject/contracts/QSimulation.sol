// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import "./IWETH9.sol";
import "./ERC20TokenTest.sol";

contract QSimulation {

    address public immutable owner;
    
    INonfungiblePositionManager public nonfungiblePositionManager;
    IWETH9 public weth;
    ERC20TokenTest public myToken;

    constructor(
        address _nonfungiblePositionManager,
        address _weth,
        uint24 _fee,
        int24 _tickLower,
        int24 _tickUpper
    ) payable {
        require(msg.value > 0, "Need ETH for liquidity");

        nonfungiblePositionManager = INonfungiblePositionManager(_nonfungiblePositionManager);
        weth = IWETH9(_weth);

        // Deploy the ERC20 token and store its address
        myToken = new ERC20TokenTest();

        // Mint tokens to this contract
        uint256 _mintAmount = 10000 * 10**18; // Adjust mint amount as needed

        // Convert ETH to WETH
        weth.deposit{value: msg.value}();

        // Approve the NonfungiblePositionManager to spend your tokens
        myToken.approve(address(nonfungiblePositionManager), _mintAmount);
        weth.approve(address(nonfungiblePositionManager), msg.value);

        // Add liquidity
        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: address(myToken) < address(weth) ? address(myToken) : address(weth),
            token1: address(myToken) < address(weth) ? address(weth) : address(myToken),
            fee: _fee,
            tickLower: _tickLower,
            tickUpper: _tickUpper,
            amount0Desired: address(myToken) < address(weth) ? _mintAmount : msg.value,
            amount1Desired: address(myToken) < address(weth) ? msg.value : _mintAmount,
            amount0Min: 0, // Adjust based on your slippage tolerance
            amount1Min: 0, // Adjust based on your slippage tolerance
            recipient: address(this),
            deadline: block.timestamp + 15 minutes // Adjust accordingly
        });

        nonfungiblePositionManager.mint(params);
    }

}
