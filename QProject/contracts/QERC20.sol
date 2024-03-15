// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract QERC20 is ERC20Permit {

    address public immutable owner;

    constructor() ERC20("Q Token", "Q")
    ERC20Permit("Q Token") {
        owner = msg.sender;
    }

    function mintReward(address account, uint256 amount) external {
        require(msg.sender == owner, "Q: caller is not Q contract.");
        require(super.totalSupply() < 5010000000000000000000000, "Q: max supply already minted");
        _mint(account, amount);
    }
}
