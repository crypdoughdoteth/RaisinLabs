// SPDX-License-Identifier: BUSL-1.1
//Copyright (C) 2022 Raisin Labs

pragma solidity 0.8.17;

import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "lib/openzeppelin-contracts/contracts/utils/math/SafeMath.sol";

contract RaisinCore is Ownable {
   using SafeMath for uint256;
    /* /////////////////////////////////////////////////////////////////
    /                                                                   /
    /                                                                   \
    /                            Events                                 /
    /                                                                   \
    /                                                                   /
    ///////////////////////////////////////////////////////////////////*/
    //add more info to FundStarted event -- amount, chain, token, goal                                 
    event FundStarted (uint indexed amount, uint64 id, uint index, IERC20 indexed token, address indexed raiser, address recipient, uint expires);
    event TokenDonated (address indexed adr, IERC20 token, uint indexed amount, uint64 indexed id, uint index);
    event TokenAdded (IERC20 indexed token);
    event FundEnded (uint64 indexed id, uint indexed index, uint indexed length);

    /* /////////////////////////////////////////////////////////////////
    /                                                                   /
    /                                                                   \
    /                          Mappings                                 /
    /                                                                   \
    /                                                                   /
    ///////////////////////////////////////////////////////////////////*/
    // address => raisins[index]._id => amount 
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
    //incrementing id
    uint64 id;
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
        //cause id
        uint64 _id;
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
        require (amount > 0, "Amount = 0");
        require(tokenWhitelist[token] = true, "Token Not Whitelisted");
        ++id;
        uint expires = getExpiry();
        raisins.push(Raisin(amount, 0, id, token, msg.sender, recipient, expires));
        emit FundStarted(amount, id, raisins.length - 1, token, msg.sender, recipient, expires);
    }

    function endFund (uint64 index) external {
        require (msg.sender == raisins[index]._raiser || msg.sender == governance);
        raisins[index]._expires = block.timestamp;
        if(raisins[index]._fundBal == 0){
            deleteFund(index);
        }
    }

    function donateToken (
        IERC20 token,
        uint64 index,
        uint amount
    ) external payable {
        require (block.timestamp < raisins[index]._expires, "Fund Not Active"); 
        require (token == raisins[index]._token, "Token Not Accepted"); 
        uint donation = calculateFee(amount, index);
        donorBal[msg.sender][raisins[index]._id] += donation;
        raisins[index]._fundBal += donation; 
        erc20Transfer(token, msg.sender, vault, (amount - donation)); 
        erc20Transfer(token, msg.sender, address(this), donation); 
        emit TokenDonated (msg.sender, token, donation, raisins[index]._id, index);

    }

    /* /////////////////////////////////////////////////////////////////
    /                                                                   /
    /                                                                   \
    /                        Withdraw/Refund Tokens                     /
    /                                                                   \
    /                                                                   /
    ///////////////////////////////////////////////////////////////////*/

    function fundWithdraw (IERC20 token, uint64 index) external payable{
        require (msg.sender == raisins[index]._raiser, "Not Your Fund");
        require(raisins[index]._fundBal >= raisins[index]._amount, "Goal Not Reached");
        require (block.timestamp >= raisins[index]._expires, "Fund Still Active");
        uint bal = raisins[index]._fundBal;
        raisins[index]._fundBal -= bal;
        deleteFund(index);
        approveTokenForContract(token, bal);
        erc20Transfer(token, address(this), raisins[index]._recipient, bal);
    }

    function refund (IERC20 token, uint64 index) external payable{
        require (block.timestamp >= raisins[index]._expires, "Fund Still Active"); 
        require(raisins[index]._fundBal < raisins[index]._amount, "Goal reached");
        uint bal = donorBal[msg.sender][raisins[index]._id];
        donorBal[msg.sender][raisins[index]._id] -= bal;
        raisins[index]._fundBal -= bal;
        if (raisins[index]._fundBal == 0) {
            deleteFund(index);
        }
        approveTokenForContract(token, bal);
        erc20Transfer(token, address(this), msg.sender, bal);
    }

    /* /////////////////////////////////////////////////////////////////
    /                                                                   /
    /                                                                   \
    /                        External Interactions                      /
    /                                                                   \
    /                                                                   /
    ///////////////////////////////////////////////////////////////////*/

    // call this function before donateToken();
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


    function deleteFund (uint64 index) internal {
       //delete array element by ID 
       //strat: mix and match
       //rationale: maximizes order preservation and cost eff. 
       // del [1]:[1,2,3,4] => [1, NULL, 3, 4] =>  [1, 4, 3, NULL] 
       raisins[index] = raisins[raisins.length - 1];
       raisins.pop();
       emit FundEnded(raisins[index]._id, index, raisins.length);
    }

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
