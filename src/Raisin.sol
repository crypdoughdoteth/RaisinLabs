// SPDX-License-Identifier: BUSL-1.1
//Copyright (C) 2022 Crypdough Labs

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
                                                            
    event FundStarted (uint32 indexed id);
    event TokenDonated (address indexed adr, IERC20 token, uint indexed amount, uint32 indexed id);
    event TokenAdded (IERC20  indexed token);
    event FundEnded (uint32 indexed id, uint indexed length);

    /* /////////////////////////////////////////////////////////////////
    /                                                                   /
    /                                                                   \
    /                          Mappings                                 /
    /                                                                   \
    /                                                                   /
    ///////////////////////////////////////////////////////////////////*/
    // address => raisins[index]._id => amount 
    mapping (address => mapping(uint32 => uint)) public donorBal;
    mapping (IERC20 => bool) public tokenWhitelist;

    /* /////////////////////////////////////////////////////////////////
    /                                                                   /
    /                                                                   \
    /                           State Variables                         /
    /                                                                   \
    /                                                                   /
    ///////////////////////////////////////////////////////////////////*/
    //incrementing id
    uint32 id;

    //withdraw address
    address vault;
    uint fee;
    //expiry time for all projects
    uint expiry;

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
        uint32 _id;
        //balance of fund
        //token to raise in 
        IERC20 _token; 
        //address of wallet raising funds
        address _raiser;
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


    constructor () {
        expiry = 180 days;
        vault = msg.sender;
        fee = 200; 
    }


    function getRaisinsLength () public view returns (uint){
        return raisins.length;
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
   
    function initFund (uint amount, IERC20 token) external {
        require (amount > 0, "Amount = 0");
        require(tokenWhitelist[token] = true, "Token Not Whitelisted");
        ++id;
        raisins.push(Raisin(amount, 0, id, token, msg.sender, getExpiry()));
        emit FundStarted(id);
    }

    function endFund (uint32 index) external {
        require (msg.sender == raisins[index]._raiser || msg.sender == owner());
        raisins[index]._expires = block.timestamp;
        if(raisins[index]._fundBal == 0){
            deleteFund(index);
        }
    }

    function donateToken (
        IERC20 token,
        uint32 index,
        uint amount
    ) external payable {
        require (block.timestamp < raisins[index]._expires, "Fund Not Active"); 
        require (token == raisins[index]._token, "Token Not Accepted"); 
        uint _fee = amount.mul(fee).div(10000);
        donorBal[msg.sender][raisins[index]._id] += amount.sub(_fee);
        raisins[index]._fundBal += amount.sub(_fee); 
        erc20Transfer(token, msg.sender, vault, _fee); 
        erc20Transfer(token, msg.sender, address(this), amount.sub(_fee)); 
        emit TokenDonated (msg.sender, token, amount.sub(_fee), raisins[index]._id);

    }

    /* /////////////////////////////////////////////////////////////////
    /                                                                   /
    /                                                                   \
    /                        Withdraw/Refund Tokens                     /
    /                                                                   \
    /                                                                   /
    ///////////////////////////////////////////////////////////////////*/

    function fundWithdraw (IERC20 token, uint32 index) external payable{
        require (msg.sender == raisins[index]._raiser, "Not Your Fund");
        require(raisins[index]._fundBal >= raisins[index]._amount, "Goal Not Reached");
        require (block.timestamp >= raisins[index]._expires, "Fund Still Active");
        uint bal = raisins[index]._fundBal;
        raisins[index]._fundBal -= bal;
        deleteFund(index);
        approveTokenForContract(token, bal);
        erc20Transfer(token, address(this), msg.sender, bal);
    }

    function refund (IERC20 token, uint32 index) external payable{
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


    function deleteFund (uint32 index) internal {
       //delete array element by ID 
       //strat: mix and match
       //rationale: maximizes order preservation and cost eff. 
       // del [1]:[1,2,3,4] => [1, NULL, 3, 4] =>  [1, 4, 3, NULL] 
       raisins[index] = raisins[raisins.length - 1];
       raisins.pop();
       emit FundEnded(index, (raisins.length + 1));
    }
    function getExpiry() private view returns (uint) {
        return block.timestamp + expiry;
    }
    //we need to store a flat amount of time here UNIX format
    function changeGlobalExpiry(uint newExpiry) external onlyOwner returns (uint){
        expiry = newExpiry; 
        return expiry;
    }
    function changeFee(uint32 newFee) external onlyOwner {
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
}
