pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import "../contracts/QPayment.sol";
import "forge-std/console.sol";

contract QPaymentTest is Test {
    QPayment public qPayment;
    HandleAIRegistration registrationHandler;
    address public user;
    address public paymentDeployer;

    uint256[] public fixtureFeeAmount = [6, 7, 8];


    function setUp() public {
        paymentDeployer = makeAddr("paymentDeployer");
        qPayment = new QPayment(paymentDeployer);
        registrationHandler = new HandleAIRegistration(qPayment);
        user = makeAddr("user");
        vm.deal(user, 6 ether);
        targetContract(address(registrationHandler));
    }

    function test_DevFeeAddrSet() public view {
        assertEq(qPayment.devFee(), paymentDeployer);
    }

    function test_RegisterAI() public{
        vm.expectEmit(address(qPayment));
        emit QPayment.AIRegisterData(user, 5 ether, "name");

        vm.prank(user);
        qPayment.aiRegister{value: 5 ether}("name");

        assertEq(address(qPayment).balance, 5 ether);
        assertEq(qPayment.aiRegisterStatus(user), true);
        assertEq(qPayment.aiAddresses(0), user);
    }

    function testFail_LateAIRegistration() public {
        vm.warp(3 days);

        vm.prank(user);
        qPayment.aiRegister{value: 7 ether}("name");
    }

    function testFail_InsufficientFeeSent() public {
        vm.startPrank(user);

        qPayment.aiRegister{value: 4.99 ether}("name");

        vm.warp(1 days);
        qPayment.aiRegister{value: 5.99 ether}("name");

        vm.warp(1 days);
        qPayment.aiRegister{value: 6.99 ether}("name");
    }

    function testFuzz_RegisterAI(uint96 feeAmount) public {
        vm.skip(true);
        vm.assume(feeAmount > 5 ether);
        
        vm.deal(user, feeAmount + 1 ether);

        vm.prank(user);
        qPayment.aiRegister{value: feeAmount}("name");
    }

    function invariant_Registered_Addresses_First_Day_Total_Payment_Balance() public {
        uint256 totalFees = registrationHandler.totalFees();
        assertEq(address(qPayment).balance, totalFees);
    }
}

contract HandleAIRegistration is Test{
    QPayment public qpaymentInstance;

    uint256 public totalFees;

    uint192 public actorSeed = 1;

    address internal currentActor;

    modifier useActor() {
        currentActor = vm.addr(actorSeed);

        vm.startPrank(currentActor);
        _;
        vm.stopPrank();

        actorSeed++;
    }

    constructor(QPayment _qpaymentInstance) {
        qpaymentInstance = _qpaymentInstance;
    }

    function callRegistration(uint256 feeAmount, uint256 waitDays) public useActor {
        waitDays = bound(waitDays, 1, 3 days);

        if(waitDays <= 1 days) {
            feeAmount = bound(feeAmount, 5 ether, 1e30);
        } else if(waitDays <= 2 days) { 
            feeAmount = bound(feeAmount, 6 ether, 1e30);
        } else {
            feeAmount = bound(feeAmount, 7 ether, 1e30);
        }

        vm.deal(currentActor, feeAmount);

        vm.warp(waitDays);
        qpaymentInstance.aiRegister{value: feeAmount}("name");

        if(waitDays <= 1 days) {
            totalFees += 5 ether;
        } else if(waitDays <= 2 days) { 
            totalFees += 6 ether;
        } else {
            totalFees += 7 ether;
        }
    }
}