// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "./Raisin.sol";
import "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC1155/ERC1155.sol";

contract RasisinTokenService is ERC1155 {
    
    RaisinCore public raisinCore;

    uint64 tokenId;

    mapping (uint64 => uint64) idToTokenId;    
    mapping (uint64 => string) public newURI;
    mapping (uint64 => uint) public threshhold;

    constructor (address raisin) ERC1155 ("Raisin","RTS"){
        raisinCore = RaisinCore(raisin);
    }

    function setThreshhold (uint64 index, uint amount) external {
        address raiser = raisinCore.raisins(index)._raiser;
        require (msg.sender == raiser, "you are not the raiser");
        threshhold[index] = amount;
    }

    function uri(uint64 index) public view virtual override returns (string memory) {
        return newURI[index];
    }
    function checkEligibility(uint64 index) public view returns (bool){
       uint64 id = raisinCore.raisins(index).id;
       uint donorBalance = raisinCore.donorBal(msg.sender ,id);
       return donorBalance >= threshhold[id] ? true:false;
    }

    function newCauseURI(uint64 index, string calldata _newURI) external {
        uint64 id = raisinCore.raisins(index).id;
        require(idToTokenId[id] == 0);
        address raiser = raisinCore.raisins(index)._raiser;
        require (msg.sender == raiser, "you are not the raiser");
        ++tokenId;
        newURI[tokenId] = _newURI;
        idToTokenId[id] = tokenId;
    }
    function tokenURI (uint64 index) public override view returns (string calldata){
        string memory baseURI = uri(index);
        return bytes(baseURI).length > 0 ? newURI(index) : "";
    }

    function mint (uint64 index) external {
        uint64 id = raisinCore.raisins(index).id;
        bool eligibile = checkEligibility(id);
        require(eligible, "Not Eligible");
        require(balanceOf(msg.sender, id) == 0);
        _mint(msg.sender, idToTokenId[id], 1, "");
    }

}
