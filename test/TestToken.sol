pragma solidity 0.8.19;

import "solmate/tokens/ERC20.sol";

contract TestToken is ERC20 {
    constructor() ERC20("TestToken", "TEST", 18) {
        _mint(msg.sender, 1000e18);
    }
}
