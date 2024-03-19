pragma solidity ^0.8.23;
import "./Q.sol";

contract QPayment {

    address public contractOwner;

    uint256 public startTime;

    uint256 public endTime;

    uint256 public cycleDuration;

    address constant forwarder = 0x0000000000000000000000000000000000000000;

    address constant devAddress = 0x0000000000000000000000000000000000000000;

    address constant dxnBuyAndBurn = 0x0000000000000000000000000000000000000000;

    address constant qBuyAndBurn = 0x0000000000000000000000000000000000000000;

    address[] public AIAddresses;

    uint256 public constant MAX_BPS = 100;

    mapping(uint256 => uint256) public feePerCycle;

    mapping(address => uint256) public aiRegisterFee;

    event AIRegisterData(address indexed AIAddress, uint256 fee, string AIName);

    event QDeployment(address indexed QContractAddress, address indexed deployer, uint256 amountSentToQ, uint256 amountSentToDeployer);

    constructor()  {
        startTime = block.timestamp;
        endTime = startTime + 3 days;
        cycleDuration = 1 days;
        feePerCycle[0] = 5 ether; 
        feePerCycle[1] = 6 ether;
        feePerCycle[2] = 7 ether;
    }

    function AIRegister(string calldata AIName) external payable {
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
        require(aiRegisterFee[msg.sender] == 0, "QPayment: AI address has already been registered!");

        if (msg.value > fee) {
            sendViaCall(payable(msg.sender), msg.value - fee);
            aiRegisterFee[msg.sender] = fee;
        } else {
            aiRegisterFee[msg.sender] = msg.value;
        }

        AIAddresses.push(msg.sender);
        emit AIRegisterData(msg.sender, fee, AIName);
    }

    function calculateCurrentCycle() public view returns (uint256) {
        return (block.timestamp - startTime) / cycleDuration;
    }

    function deployQContract() public returns(address QContractAddress) {
        require(block.timestamp > endTime,"QPayment: You cannot deploy before the three days are up!");
        uint256 userPercent = address(this).balance * 10 / MAX_BPS;
        uint256 contractPercent = address(this).balance * 90 / MAX_BPS;
        QContractAddress = (address)(new Q{value:contractPercent}(forwarder, devAddress, dxnBuyAndBurn, qBuyAndBurn, getAllAIAddresses()));
        sendViaCall(payable(msg.sender), userPercent);
        emit QDeployment(QContractAddress, msg.sender, contractPercent, userPercent);
    }

    function getAllAIAddresses() public view returns(address[] memory) {
        return AIAddresses;
    }

    function sendViaCall(address payable to, uint256 amount) internal {
        (bool sent, ) = to.call{value: amount}("");
        require(sent, "QPayment: failed to send amount");
    }

}
