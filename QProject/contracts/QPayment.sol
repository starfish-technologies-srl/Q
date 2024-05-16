// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "./Q.sol";

contract QPayment {
    uint256 public startTime;
    uint256 public endTime;
    uint256 constant cycleDuration = 1 minutes;
    uint256[3] feePerCycle = [0.000005 ether, 0.000006 ether, 0.000007 ether]; 

    address constant nxdDSV = 0xE05430D42842C7B757E5633D19ca65350E01aE11;
    address constant forwarder = 0xB2b5841DBeF766d4b521221732F9B618fCf34A87;
    address constant dxnBuyAndBurn = 0x8ff4596Cdad4F8B1e1eFaC1592a5B7b586BC5eF3;
    address public devFee;
    address public qContractAddress;
    address[] public aiAddresses;

    mapping(address => bool) public aiRegisterStatus;

    event AIRegisterData(address indexed aiAddress, uint256 fee, string aiName);

    constructor(address _devFee) {
        startTime = block.timestamp;
        endTime = startTime + 3 minutes;
        devFee = _devFee;
    }

    function aiRegister(string calldata aiName) external payable {
        require(block.timestamp >= startTime, "Early");
        require(block.timestamp <= endTime, "Late");

        uint256 currentCycle = calculateCurrentCycle();
        uint256 fee = feePerCycle[currentCycle];
        
        require(msg.value >= fee, "Fee low");
        require(!aiRegisterStatus[msg.sender], "Registered");

        aiRegisterStatus[msg.sender] = true;
        aiAddresses.push(msg.sender);

        emit AIRegisterData(msg.sender, fee, aiName);

        if (msg.value > fee) {
            sendViaCall(payable(msg.sender), msg.value - fee);
        }
    }

    function calculateCurrentCycle() public view returns (uint256) {
        return (block.timestamp - startTime) / cycleDuration;
    }

    function deployQContract() external {
        require(block.timestamp > endTime, "Early deploy");
        require(qContractAddress == address(0),"Already deployed");

        uint256 balance = address(this).balance;
        uint256 userPercent = balance * 10 / 100;
        uint256 contractPercent = balance - userPercent;

        qContractAddress = address(new Q{value: contractPercent}(forwarder, devFee, dxnBuyAndBurn, nxdDSV, aiAddresses));
        sendViaCall(payable(msg.sender), userPercent);
    }

    function sendViaCall(address payable to, uint256 amount) internal {
        (bool sent, ) = to.call{value: amount}("");
        require(sent, "Transfer fail");
    }
}
