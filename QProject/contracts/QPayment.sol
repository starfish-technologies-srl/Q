pragma solidity ^0.8.23;

contract QPayment {

    address public QMain;

    constructor() {
        QMain = msg.sender;
    }
}