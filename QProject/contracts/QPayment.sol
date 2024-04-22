// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "./Q.sol";

contract QPayment {
    uint256 public startTime;
    uint256 public endTime;
    uint256 constant cycleDuration = 1 days;
    uint256[3] feePerCycle = [5 ether, 6 ether, 7 ether]; 

    address constant forwarder = 0xB2b5841DBeF766d4b521221732F9B618fCf34A87;
    address constant dxnBuyAndBurn = 0x8ff4596Cdad4F8B1e1eFaC1592a5B7b586BC5eF3;
    address public marketingAddress;
    address public maintenanceAddress;
    address public qContractAddress;
    address[] public aiAddresses;

    mapping(address => bool) public aiRegisterStatus;

    event AIRegisterData(address indexed aiAddress, uint256 fee, string aiName);

    constructor(address _marketingAddress, address _maintenanceAddress) {
        startTime = block.timestamp;
        endTime = startTime + 3 days;
        marketingAddress = _marketingAddress;
        maintenanceAddress = _maintenanceAddress;
    }

    function aiRegister(string calldata aiName) external payable {
        require(block.timestamp >= startTime, "Early");
        require(block.timestamp <= endTime, "Late");

        uint256 currentCycle = calculateCurrentCycle();
        uint256 fee = feePerCycle[currentCycle];
        require(msg.value >= fee, "Fee low");
        require(!aiRegisterStatus[msg.sender], "Registered");

        if (msg.value > fee) {
            sendViaCall(payable(msg.sender), msg.value - fee);
        }
        aiRegisterStatus[msg.sender] = true;

        aiAddresses.push(msg.sender);
        emit AIRegisterData(msg.sender, fee, aiName);
    }

    function calculateCurrentCycle() public view returns (uint256) {
        return (block.timestamp - startTime) / cycleDuration;
    }

    function deployQContract() external {
        require(block.timestamp > endTime, "Early deploy");

        uint256 balance = address(this).balance;
        uint256 userPercent = balance * 10 / 100;
        uint256 contractPercent = balance - userPercent;

        qContractAddress = address(new Q{value: contractPercent}(forwarder, marketingAddress, maintenanceAddress, dxnBuyAndBurn, aiAddresses));
        sendViaCall(payable(msg.sender), userPercent);
    }

    function sendViaCall(address payable to, uint256 amount) internal {
        (bool sent, ) = to.call{value: amount}("");
        require(sent, "Transfer fail");
    }
}
