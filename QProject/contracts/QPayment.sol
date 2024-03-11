pragma solidity ^0.8.23;

import "@openzeppelin/contracts/access/Ownable.sol";

contract QPayment is Ownable {
    uint256 public startTime;

    uint256 public endTime;

    uint256 public cycleDuration;

    address public qContractAddress;

    mapping(address => uint256) public aiRegisterFee;

    mapping(uint256 => uint256) public totalAmountPerDay;

    mapping(uint256 => uint256) public feePerCycle;

    constructor() Ownable(msg.sender) {
        startTime = block.timestamp;
        endTime = startTime + 3 days;
        cycleDuration = 24 hours;
        feePerCycle[0] = 5 ether; 
        feePerCycle[1] = 6 ether;
        feePerCycle[2] = 7 ether;
    }

    function AIRegister(address aiAddress) external payable {
        require(
            block.timestamp >= startTime,
            "QPayment: You try to pay before starting period"
        );
        require(block.timestamp <= endTime, "QPayment: Payment time has ended");
        uint256 fee = feePerCycle[calculateCurrentCycle()];
        require(
            msg.value >= fee,
            "QPayment: The registration fee sent to the contract is insufficient"
        );

        if (msg.value > fee) {
            sendViaCall(payable(msg.sender), msg.value - fee);
            aiRegisterFee[aiAddress] += fee;
            totalAmountPerDay[calculateCurrentCycle()] += fee;
        } else {
            totalAmountPerDay[calculateCurrentCycle()] += msg.value;
            aiRegisterFee[aiAddress] += msg.value;
        }
    }

    function calculateCurrentCycle() public returns (uint256) {
        return (block.timestamp - startTime) / cycleDuration;
    }

    function setQAddress(address _qContractAddress) public onlyOwner() {
        require(_qContractAddress != address(0),"QPayment: You cannot set address 0!");
        qContractAddress = _qContractAddress;
    }

    function transferToQ(uint256 dayNumber) public onlyOwner() {
        require(qContractAddress != address(0),"QPayment: You must set QContract adress before!");
        require(dayNumber >= 0,"QPayment: Day number must be >= 0!");
        require(dayNumber <= 2,"QPayment: Day number must be <= 2!");
        sendViaCall(payable(qContractAddress), totalAmountPerDay[dayNumber]);
        totalAmountPerDay[dayNumber] = 0;
    }

    function sendViaCall(address payable to, uint256 amount) internal {
        (bool sent, ) = to.call{value: amount}("");
        require(sent, "QPayment: failed to send amount");
    }

    function emergencyWithdraw() public onlyOwner() {
        sendViaCall(payable(msg.sender), address(this).balance);
    }
}
