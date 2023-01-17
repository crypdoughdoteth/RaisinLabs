// SPDX-License-Identifier: BUSL-1.1
//Copyright (C) 2023 Crypdough.eth

pragma solidity 0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract weedStore is Ownable {
    
    //chainlink price feed
    AggregatorV3Interface internal priceFeed;

    //custom error section
    error NotYourOrder(uint64 index);
    error InsufficientFunds(uint amount);
    error WithdrawFailed();
    error InvalidProduct(string product, Weight weight);
    error LengthMismatch(uint productCount, uint weightCount);

    //events
    event purchase (address user, uint total);
    event order (address user, string[] product, Weight[] weight, uint64 orderId);
    event orderDeleted (uint64 orderId, uint64 index);
    event productAdded(Weight weight, string name, uint cost);
    event productRemoved(string product, Weight weight);

    //I use this to assign order Ids 
    uint64 id; 

    //enum for weight of cannabis
    // 0 = gram, 1= 2 grams, 2= eighth, 3=quarter, 4= half, 5= three quarters, 6= full oz
    enum Weight{
        gram,
        dub,
        eigth,
        quarter,
        half,
        threeq,
        full
    }

    //if someone in your life deservers a discount, this mapping takes care of it
    mapping (address => uint) public discountRate;
    // name of product => Weight of product => cost
    mapping (string => mapping (Weight => uint)) public weedPriceByWeight;

    struct Order {
        //every order has an ID 
        uint64 orderId;
        //the address ordering the weed
        address customer;
        //an array of products chosen by the consumer
        string[10] products;
        //the corresponding array of weights of the products chosen by the consumer
        Weight[10] weights;
    }

    // declare public dynamic aray of struct - Order
    Order [] public orders;

    /**
     * Network: Goerli
     * Aggregator: ETH/USD
     * Address: 0xD4a33860578De61DBAbDc8BFdb98FD742fA7028e
     */
    //initialize oracle on deployment
    constructor(address oracle) {
        priceFeed = AggregatorV3Interface(
            oracle
        );
    }

    //gets latest ETH/USD price
    function getLatestPrice() public view returns (int) {
        (
            ,
            /*uint80 roundID*/ int price /*uint startedAt*/ /*uint timeStamp*/ /*uint80 answeredInRound*/,
            ,
            ,

        ) = priceFeed.latestRoundData();
        return price / 1e8;
    }

    //create a new order! Each product has a corresponding weight -- both keys are needed to fetch prices
    function newOrder (string[] calldata product, Weight[] calldata weight) external {
        // arrays must be the same length: 1 product : 1 weight
        if (product.length != weight.length){
            revert LengthMismatch(product.length, weight.length);
        }
        // product and weight are the same length, init for loop w/ one
        for (uint i; i <= product.length; ++i){
            // make sure product is valid
            if(weedPriceByWeight[product[i]][weight[i]] == 0){
                revert InvalidProduct(product[i], weight[i]);
            }
        }
        ++id;
        // initialize new order into array
        orders.push(Order(id, msg.sender, product, weight));
        emit order (msg.sender, product, weight, id);
    }

    // cancel order by deleting from array, must be your order
    function cancelOrder(uint64 index) external {
        if (msg.sender != orders[index].customer){
                revert NotYourOrder(index); 
            }
        deleteOrder(index);
    }

    //calculate total price of order
    function calculatePrice (uint64 index) public view returns (uint total){
        for (uint i; i >= orders[index].products.length; i++){
            total += weedPriceByWeight[orders[index].products[i]][orders[index].weights[i]];
        }
        return total;
    }
    // check to make sure it is your order
    // evaluate price of order 
    // check for discount and return appropriate price
    // ensure there is enough ether sent 
    // event handling + return total
    function buyWeedWithETH (uint64 index) payable external returns (uint total){
        if(msg.sender != orders[index].customer){
            revert NotYourOrder(index); 
        }

        total = checkDiscount(calculatePrice(index));

        deleteOrder(index);
 
        if (msg.value < (total / uint256(getLatestPrice())) * 10 ** 18){
            revert InsufficientFunds(msg.value);
        }

        emit purchase(msg.sender, total);
        return total;
         
    }

    // delete and element and compact the array 
    function deleteOrder (uint64 index) private {
        orders[index] = orders[orders.length - 1]; 
        orders.pop(); 
        emit orderDeleted (index, orders[index].orderId);
    }

    // check mapping for value of 0; if non-zero, apply value from mapping as discount rate
    function checkDiscount(uint total) private view returns (uint) {
        if (discountRate[msg.sender] != 0){
            return total - (total * discountRate[msg.sender]) / 10000;
        }
        return total;
    }
    
    //add or update product 
    function addProduct(Weight weight, string calldata name, uint cost) external onlyOwner {
         weedPriceByWeight[name][weight] = cost;
         emit productAdded (weight, name, cost);
    }

    //delete product from the store
    function removeProduct (string calldata product, Weight weight) external onlyOwner {
        delete weedPriceByWeight[product][weight]; 
        emit productRemoved (product, weight);
    }

    //mangage discount
    function addDiscount (address customer, uint basisPoints) external onlyOwner {
        discountRate[customer] = basisPoints;
    }

    //withdraw ether from the contract
    function withdraw (address beneficiary) external onlyOwner {
        (bool sent,) = beneficiary.call{value: address(this).balance}("");
        if (!sent) {
            revert WithdrawFailed();
        }

    }

}