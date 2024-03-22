// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;
import "./Q.sol";

contract QPayment {
    uint256 public startTime;
    uint256 public endTime;
    uint256 public cycleDuration = 1 days;
    address constant forwarder = 0x0000000000000000000000000000000000000000;
    address constant devAddress = 0x0000000000000000000000000000000000000000;
    address constant dxnBuyAndBurn = 0x0000000000000000000000000000000000000000;
    address constant qBuyAndBurn = 0x0000000000000000000000000000000000000000;
    address[] public AIAddresses;

    uint256 public constant MAX_BPS = 100;
    uint256[3] public feePerCycle = [5 ether, 6 ether, 7 ether]; 

    mapping(address => uint256) public aiRegisterFee;

    event AIRegisterData(address indexed AIAddress, uint256 fee, string AIName);

    constructor() {
        startTime = block.timestamp;
        endTime = startTime + 3 days;
    }

    function AIRegister(string calldata AIName) external payable {
        require(block.timestamp >= startTime, "Early");
        require(block.timestamp <= endTime, "Late");

        uint256 currentCycle = calculateCurrentCycle();
        uint256 fee = feePerCycle[currentCycle];
        require(msg.value >= fee, "Fee low");
        require(aiRegisterFee[msg.sender] == 0, "Registered");

        if (msg.value > fee) {
            sendViaCall(payable(msg.sender), msg.value - fee);
        }
        aiRegisterFee[msg.sender] = fee;

        AIAddresses.push(msg.sender);
        emit AIRegisterData(msg.sender, fee, AIName);
    }

    function calculateCurrentCycle() public view returns (uint256) {
        return (block.timestamp - startTime) / cycleDuration;
    }

    function deployQContract() external returns (address QContractAddress) {
        require(block.timestamp > endTime, "Early deploy");

        uint256 balance = address(this).balance;
        uint256 userPercent = balance * 10 / MAX_BPS;
        uint256 contractPercent = balance * 90 / MAX_BPS;

        QContractAddress = address(new Q{value: contractPercent}(forwarder, devAddress, dxnBuyAndBurn, qBuyAndBurn, AIAddresses));
        sendViaCall(payable(msg.sender), userPercent);
    }

    function sendViaCall(address payable to, uint256 amount) internal {
        (bool sent, ) = to.call{value: amount}("");
        require(sent, "Transfer fail");
    }
}
