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
        raisin = new RaisinCore(address(this));  
        tt.approve(address(raisin), 10000000000000000000000e18);
        raisin.whitelistToken(tt);
    }

    //passing tests
    function testHappyCase(uint amount) public {
        vm.assume(amount >= 100);
        vm.assume(amount <= tt.totalSupply() - ((tt.totalSupply() * 200)/10000));
        raisin.initFund(amount, tt, address(this));
        raisin.donateToken(tt, 0, amount + (tt.totalSupply() * 200)/10000);
        raisin.endFund(0);
        raisin.fundWithdraw(0);
    }
    function testFailHappyCaseInvariant(uint amount) public {
        vm.assume(amount >= 100);
        vm.assume(amount <= tt.totalSupply() - ((tt.totalSupply() * 200)/10000));
        raisin.initFund(amount, tt, address(this));
        raisin.donateToken(tt, 0, amount + (tt.totalSupply() * 200)/10000);
        raisin.endFund(0);
        raisin.refund(0);
    }
    function testBaseCase(uint amount) public{
        vm.assume(amount >= 100);
        vm.assume(amount <= tt.totalSupply());
        raisin.initFund(amount, tt, address(this));
        raisin.donateToken(tt, 0, amount - 1);
        raisin.endFund(0);
        raisin.refund(0);
    }

    function testFailBaseCaseInvariant(uint amount) public{
        vm.assume(amount >= 100);
        vm.assume(amount <= tt.totalSupply());
        raisin.initFund(amount, tt, address(this));
        raisin.donateToken(tt, 0, amount - 1);
        raisin.endFund(0);
        raisin.fundWithdraw(0);
    }

    function testNil() public {
        raisin.initFund(5e18, tt, address(this));
        raisin.endFund(0);
    }

    function testDiscount() public{
        raisin.initFund(5e18, tt, address(this));
        raisin.donateToken(tt, 0, 6e18);
        raisin.manageDiscount(address(this), 100);
        raisin.initFund(5e18, tt, address(this));
        raisin.donateToken(tt, 1, 6e18);
        assertEq(((6e18-raisin.getFundBal(0))/2), 6e18-raisin.getFundBal(1));
    }

    function testMixedCase(uint amount, address beneficiary, uint donation) public {
        vm.assume(beneficiary != address(0));
        vm.assume(amount >= 100 && amount <= tt.totalSupply() - ((tt.totalSupply() * 200)/10000));
        vm.assume(donation > 100 && donation <= tt.totalSupply() - ((tt.totalSupply() * 200)/10000));
        raisin.initFund(amount, tt, beneficiary);
        raisin.donateToken(tt, raisin.getLength() - 1, donation);
        raisin.endFund(raisin.getLength() - 1);
        if(raisin.getFundBal(raisin.getLength() - 1) < raisin.getAmount(raisin.getLength() - 1)){
            raisin.refund(raisin.getLength() - 1);        
        }
        else{
            raisin.fundWithdraw(raisin.getLength() - 1);
        }
    }
    function testFailMixedCaseInvariants(uint amount, address beneficiary, uint donation) public {
        vm.assume(beneficiary != address(0));
        vm.assume(amount >= 100 && amount <= tt.totalSupply() - ((tt.totalSupply() * 200)/10000));
        vm.assume(donation > 100 && donation <= tt.totalSupply() - ((tt.totalSupply() * 200)/10000));
        raisin.initFund(amount, tt, beneficiary);
        raisin.donateToken(tt, raisin.getLength() - 1, donation);
        raisin.endFund(raisin.getLength() - 1);
        if(raisin.getFundBal(raisin.getLength() - 1) >= raisin.getAmount(raisin.getLength() - 1)){
            raisin.refund(raisin.getLength() - 1);        
      
        }
        else{
            raisin.fundWithdraw(raisin.getLength() - 1);
        }
    }

}
