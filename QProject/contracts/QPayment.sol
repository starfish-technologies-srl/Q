pragma solidity ^0.8.23;
import "./Q.sol";

contract QPayment {
    address public contractOwner;

    uint256 public startTime;

    uint256 public endTime;

    uint256 public cycleDuration;

    uint256 public constant MAX_BPS = 100;

    mapping(address => uint256) public aiRegisterFee;

    mapping(uint256 => uint256) public feePerCycle;

    address constant forwarder;

    address constant devAddress;

    address constant dxnBuyAndBurn;

    address constant qBuyAndBurn;

    event AIRegisterData(address indexed AIOwner, address indexed AIAddress, uint256 fee);

    event QDeployment(address indexed QContractAddress, address indexed deployer, uint256 amountSentToQ, uint256 amountSentToDeployer);

    constructor()  {
        startTime = block.timestamp;
        endTime = startTime + 3 minutes;
        cycleDuration = 1 minutes;
        feePerCycle[0] = 5 ether; 
        feePerCycle[1] = 6 ether;
        feePerCycle[2] = 7 ether;
    }

    function AIRegister(address aiAddress) external payable {
        require(
            block.timestamp >= startTime,
            "QPayment: You try to pay before starting period!"
        );
        require(block.timestamp <= endTime, "QPayment: Payment time has ended!");
        uint256 fee = feePerCycle[calculateCurrentCycle()];
        require(
            msg.value >= fee,
            "QPayment: The registration fee sent to the contract is insufficient!"
        );
        require(aiRegisterFee[aiAddress] == 0, "QPayment: AI address has already been registered!");

        if (msg.value > fee) {
            sendViaCall(payable(msg.sender), msg.value - fee);
            aiRegisterFee[aiAddress] = fee;
        } else {
            aiRegisterFee[aiAddress] = msg.value;
        }

        emit AIRegisterData(msg.sender, aiAddress, fee);
    }

    function calculateCurrentCycle() public returns (uint256) {
        return (block.timestamp - startTime) / cycleDuration;
    }

    function deployQContract() public returns(address QContractAddress) {
        require(block.timestamp > endTime,"QPayment: Cannot send balance!");
        uint256 userPercent = address(this).balance * 10 / MAX_BPS;
        uint256 contractPercent = address(this).balance * 90 / MAX_BPS;
        QContractAddress = new Q(forwarder, devAddress, dxnBuyAndBurn, qBuyAndBurn);
        sendViaCall(payable(msg.sender), userPercent);
        sendViaCall(payable(QContractAddress), contractPercent);

        emit QDeployment(QContractAddress, msg.sender, contractPercent, userPercent, block.timestamp);
    }

    function sendViaCall(address payable to, uint256 amount) internal {
        (bool sent, ) = to.call{value: amount}("");
        require(sent, "QPayment: failed to send amount");
    }

}
