// SPDX-License-Identifier: BUSL-1.1
//Copyright (C) 2022 Raisin Labs

pragma solidity 0.8.17;

import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "lib/openzeppelin-contracts/contracts/utils/math/SafeMath.sol";

contract RaisinCore is Ownable {
   using SafeMath for uint256;

   //custom errors
   error zeroGoal(uint);
   error tokenNotWhitelisted(IERC20);
   error notYourRaisin(uint64);
   error raisinExpired();
   error raisinActive();
   error goalNotReached();
   error goalReached();

    /* /////////////////////////////////////////////////////////////////
    /                                                                   /
    /                                                                   \
    /                            Events                                 /
    /                                                                   \
    /                                                                   /
    ///////////////////////////////////////////////////////////////////*/
    event FundStarted (uint indexed amount, uint index, IERC20 indexed token, address indexed raiser, address recipient, uint expires);
    event TokenDonated (address indexed adr, IERC20 token, uint indexed amount, uint index);
    event TokenAdded (IERC20 indexed token);
    event FundEnded (uint indexed index);

    /* /////////////////////////////////////////////////////////////////
    /                                                                   /
    /                                                                   \
    /                          Mappings                                 /
    /                                                                   \
    /                                                                   /
    ///////////////////////////////////////////////////////////////////*/

    mapping (address => mapping(uint64 => uint)) public donorBal;
    mapping (IERC20 => bool) public tokenWhitelist;
    mapping (address => uint) private partnership;

    /* /////////////////////////////////////////////////////////////////
    /                                                                   /
    /                                                                   \
    /                           State Variables                         /
    /                                                                   \
    /                                                                   /
    ///////////////////////////////////////////////////////////////////*/
    //withdraw address
    address private vault;
    uint public fee;
    //expiry time for all projects
    uint public expiry;
    address public governance;

    /* /////////////////////////////////////////////////////////////////
    /                                                                   /
    /                                                                   \
    /                            Structs                                /
    /                                                                   \
    /                                                                   /
    ///////////////////////////////////////////////////////////////////*/
    struct Raisin  {
        //raise goal amount in native token 
        uint _amount;
        uint _fundBal;
        //balance of fund
        //token to raise in 
        IERC20 _token; 
        //address of wallet raising funds
        address _raiser;
        address _recipient;
        //timestamp expiry 
        uint _expires;        
    }
    /* /////////////////////////////////////////////////////////////////
    /                                                                   /
    /                                                                   \
    /                            Array + Constructor                    /
    /                                                                   \
    /                                                                   /
    ///////////////////////////////////////////////////////////////////*/

    Raisin [] public raisins; 


    constructor (address treasury, address governanceMultisig) {
        expiry = 180 days;
        vault = treasury;
        fee = 200; 
        governance = governanceMultisig;
    }


    /* /////////////////////////////////////////////////////////////////
    /                                                                   /
    /                                                                   \
    /                         Fund Functions                            /
    /                                                                   \
    /                                                                   /
    ///////////////////////////////////////////////////////////////////*/

   //starts fund for user
   //@param amount: amount of tokens being raised
   //@param token: token raised in
   
    function initFund (uint amount, IERC20 token, address recipient) external {
        if (amount == 0){revert zeroGoal(amount);}
        if(tokenWhitelist[token] != true){revert tokenNotWhitelisted(token);}
        uint expires = getExpiry();
        raisins.push(Raisin(amount, 0, token, msg.sender, recipient, expires));
        emit FundStarted(amount, raisins.length - 1, token, msg.sender, recipient, expires);
    }

    function endFund (uint64 index) external {
        if (msg.sender != raisins[index]._raiser || msg.sender != governance){revert notYourRaisin(index);}
        raisins[index]._expires = block.timestamp;
        if(raisins[index]._fundBal == 0){emit FundEnded(index);}
    }

    function donateToken (
        IERC20 token,
        uint64 index,
        uint amount
    ) external payable {
        if (block.timestamp >= raisins[index]._expires){revert raisinExpired();} 
        if (token != raisins[index]._token){revert tokenNotWhitelisted(token);} 
        uint donation = amount - calculateFee(amount, index);
        donorBal[msg.sender][index] += donation;
        raisins[index]._fundBal += donation; 
        erc20Transfer(token, msg.sender, vault, (amount - donation)); 
        erc20Transfer(token, msg.sender, address(this), donation); 
        emit TokenDonated (msg.sender, token, donation, index);

    }

    /* /////////////////////////////////////////////////////////////////
    /                                                                   /
    /                                                                   \
    /                        Withdraw/Refund Tokens                     /
    /                                                                   \
    /                                                                   /
    ///////////////////////////////////////////////////////////////////*/

    function fundWithdraw (IERC20 token, uint64 index) external payable{
        if(raisins[index]._fundBal < raisins[index]._amount){revert goalNotReached();}
        if (block.timestamp < raisins[index]._expires){revert raisinActive();}
        uint bal = raisins[index]._fundBal;
        raisins[index]._fundBal = 0;
        approveTokenForContract(token, bal);
        erc20Transfer(token, address(this), raisins[index]._recipient, bal);
        emit FundEnded(index);
    }

    function refund (IERC20 token, uint64 index) external payable{
        if (block.timestamp < raisins[index]._expires){revert raisinActive();} 
        if (raisins[index]._fundBal >= raisins[index]._amount){revert goalReached();}
        uint bal = donorBal[msg.sender][index];
        donorBal[msg.sender][index] -= bal;
        raisins[index]._fundBal -= bal;
        approveTokenForContract(token, bal);
        erc20Transfer(token, address(this), msg.sender, bal);
        if (bal == 0){emit FundEnded(index);}
    }

    /* /////////////////////////////////////////////////////////////////
    /                                                                   /
    /                                                                   \
    /                        External Interactions                      /
    /                                                                   \
    /                                                                   /
    ///////////////////////////////////////////////////////////////////*/

    function approveTokenForContract (
        IERC20 token,
        uint amount
    ) private {
        bool sent = token.approve(address(this), amount);
        require(sent, "approval failed");
    }

    function erc20Transfer (
        IERC20 token,
        address sender,
        address recipient,
        uint amount
        ) private {
        bool sent = token.transferFrom(sender, recipient, amount); 
        require(sent, "Token transfer failed"); 
    }

    /* /////////////////////////////////////////////////////////////////
    /                                                                   /
    /                                                                   \
    /                               Admin                               /
    /                                                                   \
    /                                                                   /
    ///////////////////////////////////////////////////////////////////*/

    function manageDiscount (address partnerWallet, uint newFee) external onlyOwner {
        partnership[partnerWallet] = newFee;
    }
    function getExpiry() private view returns (uint) {
        return block.timestamp + expiry;
    }
    function calculateFee(uint amount, uint64 index) private view returns (uint _fee){
        uint pf = partnership[raisins[index]._raiser];
        return pf != 0 ? _fee = amount.mul(pf).div(10000) : _fee = amount.mul(fee).div(10000);
    }
    //we need to store a flat amount of time here UNIX format
    function changeGlobalExpiry(uint newExpiry) external onlyOwner returns (uint){
        expiry = newExpiry; 
        return expiry;
    }
    function changeFee(uint64 newFee) external onlyOwner {
        require (newFee != 0 && newFee != fee);
        fee = newFee; 
    }
    function whitelistToken (IERC20 token) external onlyOwner {
        tokenWhitelist[token] = true; 
        emit TokenAdded(token); 
    }

    function removeWhitelist(IERC20 token) external onlyOwner {
        tokenWhitelist[token] = false; 
    }

    function changeVault(address newAddress) external onlyOwner {
        require(newAddress != address(0));
        vault = newAddress;
    }

    function changeGovernanceWallet(address newGovWallet) external onlyOwner {
        require (newGovWallet != address(0));
        governance = newGovWallet;
    }
}
