// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "lib/forge-std/src/Test.sol";
import "../src/Raisin.sol";
import "../src/TestToken.sol";

abstract contract HelperContract {
    TestToken public tt;
    constructor() {
        tt = new TestToken();
    }

}

contract ContractTest is Test, HelperContract {
    
    RaisinCore public raisin;

    function setUp() public {

        raisin = new RaisinCore(address(this), msg.sender);  
        tt.approve(address(raisin), 100e18);
        raisin.whitelistToken(tt);
        raisin.manageDiscount(address(this), 100);
    }

    //passing tests
    function testHappyCase() public {
        raisin.initFund(5e18, tt, address(this));
        raisin.donateToken(tt, 0, 6e18);
        raisin.endFund(0);
        raisin.fundWithdraw(tt, 0);
    }
    function testBaseCase() public{
        raisin.initFund(5e18, tt, address(this));
        raisin.donateToken(tt, 0, 4e18);
        raisin.endFund(0);
        raisin.refund(tt, 0);
    }

    function testNil() public {
        raisin.initFund(5e18, tt, address(this));
        raisin.endFund(0);
    }
}
