pragma solidity ^0.8.0;
import "./QBuyBurn.sol";

contract Attack {
    QBuyBurn swapper;

    constructor(address _swapper) {
        swapper = QBuyBurn(payable(_swapper));
    }

    receive() external payable {}

    function setSwapper(address _swapper) public {
        swapper = QBuyBurn(payable(_swapper));
    }
    function attack() public payable {
        sendViaCall(payable(swapper),msg.value);
    }

      function sendViaCall(address payable to, uint256 amount) internal {
        (bool sent, ) = to.call{value: amount}("");
        require(sent, "DBXen: failed to send amount");
    }
}