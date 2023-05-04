// SPDX-License-Identifier: BUSL-1.1
//Copyright (C) 2023 Raisin Labs

pragma solidity 0.8.19;
//Library: Solmate
import "./src/utils/SafeTransferLib.sol";
import "./src/tokens/ERC20.sol";
import "./src/utils/ReentrancyGuard.sol";

contract RaisinCore is ReentrancyGuard {
    using SafeTransferLib for ERC20;
   //custom errors
    error zeroGoal(uint256);
    error tokenNotWhitelisted(ERC20);
    error notYourRaisin(uint256);
    error raisinExpired();
    error raisinActive();
    error goalNotReached();
    error goalReached();
    error notSent();
    error arrayLengthMismatch();

    /* /////////////////////////////////////////////////////////////////
    /                                                                   /
    /                                                                   \
    /                            Events                                 /
    /                                                                   \
    /                                                                   /
    ///////////////////////////////////////////////////////////////////*/
    event FundStarted (uint256 indexed amount, uint256 index, ERC20 indexed token, address indexed raiser, address recipient, uint64 expires);
    event TokenDonated (address adr, ERC20 indexed token, uint256 indexed amount, uint256 indexed index);
    event TokenAdded (ERC20 indexed token);
    event FundEnded (uint256 indexed index);
    event Withdraw (ERC20 indexed token, uint256 indexed amount);
    // solmate/auth/owned.sol
    event OwnershipTransferred(address indexed user, address indexed newOwner);

    /* /////////////////////////////////////////////////////////////////
    /                                                                   /
    /                                                                   \
    /                          Mappings                                 /
    /                                                                   \
    /                                                                   /
    ///////////////////////////////////////////////////////////////////*/

    mapping (address => mapping(uint256 => uint256)) public donorBal;
    mapping (ERC20 => bool) public tokenWhitelist;
    mapping (address => Partner) private partnership;

    /* /////////////////////////////////////////////////////////////////
    /                                                                   /
    /                                                                   \
    /                           State Variables                         /
    /                                                                   \
    /                                                                   /
    ///////////////////////////////////////////////////////////////////*/
    //withdraw address
    address private vault;
    uint256 public fee;
    //expiry time for all projects
    uint64 public expiry;
    address public owner;
    /* /////////////////////////////////////////////////////////////////
    /                                                                   /
    /                                                                   \
    /                            Structs                                /
    /                                                                   \
    /                                                                   /
    ///////////////////////////////////////////////////////////////////*/
    struct Raisin  {
        //raise goal amount in native token 
        uint256 _amount;
        uint256 _fundBal;
        //balance of fund
        //token to raise in 
        ERC20 _token; 
        //address of wallet raising funds
        address _raiser;
        address _recipient;
        //timestamp expiry 
        uint64 _expires;        
    }

    struct Partner {
        uint16 fee;
        bool active;
    }

    /* /////////////////////////////////////////////////////////////////
    /                                                                   /
    /                                                                   \
    /                            Array + Constructor                    /
    /                                                                   \
    /                                                                   /
    ///////////////////////////////////////////////////////////////////*/

    Raisin [] public raisins; 
    // solmate/auth/owned.sol
    modifier onlyOwner() virtual {
        require(msg.sender == owner, "UNAUTHORIZED");

        _;
    }

    constructor (address treasury) {
        require(treasury != address(0));
        owner = msg.sender;
        expiry = 180 days;
        vault = treasury;
        fee = 200; 
    }


    function getAmount(uint256 index) public view returns (uint256){
        return raisins[index]._amount;
    }
    function getFundBal(uint256 index) public view returns (uint256){
        return raisins[index]._fundBal;
    }    
    function getToken(uint256 index) public view returns (ERC20){
        return raisins[index]._token;
    }    
    function getRaiser(uint256 index) public view returns (address){
        return raisins[index]._raiser;
    }    
    function getRecipient(uint256 index) public view returns (address){
        return raisins[index]._recipient;
    }    
    function getExpires(uint256 index) public view returns (uint64){
        return raisins[index]._expires;
    }

    function getLength() public view returns (uint256){
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
   
    function initFund (uint256 amount, ERC20 token, address recipient) external {
        if (amount < 100){revert zeroGoal(amount);}
        if(tokenWhitelist[token] != true){revert tokenNotWhitelisted(token);}
        if(recipient == address(0)){revert();}
        uint64 expires = getExpiry();
        raisins.push(Raisin(amount, 0, token, msg.sender, recipient, expires));
        emit FundStarted(amount, raisins.length - 1, token, msg.sender, recipient, expires);
    }

    function endFund (uint256 index) external {
        Raisin memory _raisin = raisins[index];
        if (msg.sender != _raisin._raiser){revert notYourRaisin(index);}
        raisins[index]._expires = uint64(block.timestamp);
        emit FundEnded(index);
    }

    function donateToken (
        ERC20 token,
        uint256 index,
        uint256 amount
    ) external nonReentrant {
        Raisin memory _raisin = raisins[index];
        if (uint64(block.timestamp) > _raisin._expires){revert raisinExpired();} 
        if (token != _raisin._token){revert tokenNotWhitelisted(token);} 
        uint256 before = token.balanceOf(address(this));
        uint256 donation = amount - calculateFee(amount, _raisin._raiser);
        SafeTransferLib.safeTransferFrom(token, msg.sender, vault, (amount - donation)); 
        SafeTransferLib.safeTransferFrom(token, msg.sender, address(this), donation); 
        uint256 diff = token.balanceOf(address(this)) - before;
        donorBal[msg.sender][index] += diff;
        raisins[index]._fundBal += diff;
        emit TokenDonated (msg.sender, token, donation, index);
    }

    function batchTokenDonate(ERC20[] calldata tokens, uint256[] calldata indices, uint256[] calldata amount) external nonReentrant{
        if (tokens.length != indices.length || tokens.length != amount.length || indices.length != amount.length){revert arrayLengthMismatch();}
        for(uint i = 0; i < indices.length; ++i){
            Raisin memory _raisin = raisins[indices[i]];
            if (uint64(block.timestamp) > _raisin._expires){revert raisinExpired();} 
            if (tokens[i] != _raisin._token){revert tokenNotWhitelisted(tokens[i]);} 
            uint256 before = _raisin._token.balanceOf(address(this));
            uint256 donation = amount[i] - calculateFee(amount[i], _raisin._raiser);
            SafeTransferLib.safeTransferFrom(tokens[i], msg.sender, vault, (amount[i] - donation)); 
            SafeTransferLib.safeTransferFrom(tokens[i], msg.sender, address(this), donation); 
            uint256 diff = _raisin._token.balanceOf(address(this)) - before;
            donorBal[msg.sender][indices[i]] += diff;
            raisins[indices[i]]._fundBal += diff;
            emit TokenDonated (msg.sender, tokens[i], donation, indices[i]);
        }
    }

    /* /////////////////////////////////////////////////////////////////
    /                                                                   /
    /                                                                   \
    /                        Withdraw/Refund Tokens                     /
    /                                                                   \
    /                                                                   /
    ///////////////////////////////////////////////////////////////////*/

    function fundWithdraw (uint256 index) external{
        Raisin memory _raisin = raisins[index];
        if(_raisin._fundBal <= _raisin._amount){revert goalNotReached();}
        if (uint64(block.timestamp) < _raisin._expires){revert raisinActive();}
        uint256 bal = _raisin._fundBal;
        raisins[index]._fundBal = 0;
        ERC20 token = _raisin._token;
        SafeTransferLib.safeTransfer(token, _raisin._recipient, bal);
        emit FundEnded(index);
    }

    function refund (uint256 index) external {
        Raisin memory _raisin = raisins[index];
        if (uint64(block.timestamp) < _raisin._expires){revert raisinActive();} 
        if (raisins[index]._fundBal >= _raisin._amount){revert goalReached();}
        uint256 bal = donorBal[msg.sender][index];
        donorBal[msg.sender][index] = 0;
        raisins[index]._fundBal -= bal;
        ERC20 token = _raisin._token;
        SafeTransferLib.safeTransfer(token, msg.sender, bal);
        emit Withdraw(token, bal);
    }

    /* /////////////////////////////////////////////////////////////////
    /                                                                   /
    /                                                                   \
    /                               Admin                               /
    /                                                                   \
    /                                                                   /
    ///////////////////////////////////////////////////////////////////*/

    function getExpiry() private view returns (uint64) {
        return uint64(block.timestamp) + expiry;
    }
    function calculateFee(uint256 amount, address raiser) private view returns (uint256 _fee){
  
        if (partnership[raiser].active) {
            _fee = (amount * partnership[raiser].fee) / 10000; 
        } else {
            _fee = (amount * fee) / 10000;
        }

    }
    //we need to store a flat amount of time here UNIX format padded to 32 bytes
    function changeGlobalExpiry(uint256 newExpiry) external payable onlyOwner returns (uint64){
        expiry = uint64(newExpiry); 
        return expiry;
    }
    function changeFee(uint16 newFee) external payable onlyOwner {
        require (newFee <= 300);
        partnership[msg.sender].fee = newFee; 
    }
    function togglePartnership() external payable onlyOwner{
        !partnership[msg.sender].active; 
    }

    function whitelistToken (ERC20 token) external payable onlyOwner {
        tokenWhitelist[token] = true; 
        emit TokenAdded(token); 
    }

    function removeWhitelist(ERC20 token) external payable onlyOwner {
        tokenWhitelist[token] = false; 
    }

    function changeVault(address newAddress) external payable onlyOwner {
        require(newAddress != address(0));
        vault = newAddress;
    }
    
    // solmate/auth/owned.sol
    function transferOwnership(address newOwner) public payable virtual onlyOwner {
        owner = newOwner;

        emit OwnershipTransferred(msg.sender, newOwner);
    }
}
