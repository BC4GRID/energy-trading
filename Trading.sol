// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "./TokenDispenser.sol";

struct TradeOffer {
    address payable sellerAddress;
    uint256 energyAmount;
    uint validUntil; //unix timestamp 
    uint pricePerEnergyAmount; //in Wei
    bool exists; //flag for reading from mapping
}

contract Trading {
    address private owner;
    uint256 private currentId;
    address private epAddress;
    TokenDispenser private ep;

    mapping (uint256 => TradeOffer) public offers;

    //event that fires when an offer is created
    event OfferCreated(uint256 id, address seller, uint validUntil, uint pricePerEnergyAmount, uint256 energyAmount);

    //event that fires when offer is modified
    event OfferModified(uint256 id, address seller, uint validUntil, uint pricePerEnergyAmount, uint256 energyAmount);
    
    //event that fires when offer is closed (sold or expired)
    event OfferClosed(uint256 id);


    function getID() private returns (uint256) {
        currentId++;
        return currentId;
    }

    constructor(address TokenDispenserContractAddress) {
        epAddress = TokenDispenserContractAddress;
        ep = TokenDispenser(TokenDispenserContractAddress);
        owner = msg.sender;
    }

    /* Method used by energy seller to create an offer. Fires OfferCreated event.
    
    NOTE: Before creating an offer, for security reasons, the seller must
    authorize this smart contract to transfer tokens in seller's name using increaseAllowance method of ERC20 token: 
    increaseAllowance(contractAddress, energyAmount).

    Params:
    validUntil - Unix timestamp that marks the time when the offer ends
    pricePerEnergyAmount - price, in Wei, for every unit of energy being sold
    energyAmount - the amount of energy (tokens) for sell
    */
    function CreateEnergyOffer(uint validUntil, uint pricePerEnergyAmount, uint256 energyAmount) public {
        require(ep.IsRegistered(msg.sender), "Only registered user (meter) may make sell offers");
        require(energyAmount <= ep.balanceOf(msg.sender), "Must have tokens to sell.");
        require(validUntil > block.timestamp,"Offer deadline must be in the future.");//TODO: videti koliko u buducnosti, jer block.timestamp nije bas trenutno vreme
        ep.transferFrom(msg.sender, address(this), energyAmount);
        uint256 id = getID();

        offers[id] = TradeOffer({
            sellerAddress: payable(msg.sender), 
            energyAmount:energyAmount,
            validUntil: validUntil,
            pricePerEnergyAmount: pricePerEnergyAmount,
            exists: true});
        emit OfferCreated(id, msg.sender, validUntil, pricePerEnergyAmount, energyAmount);
    }

    /* Method used by energy buyers to buy energy from an offer. The buyer doesn't need to buy all energy from the offer. Fires OfferModified or OfferClosed events.
    When method is closed, seller may recover remaining unsold tokens using RetrieveTokens method.
    
    NOTE: Method is payable, which means that buyer must send at least energyAmount*offers[offerId].pricePerEnergyAmount Weis when calling this method.

    Params:
    offerId - unique id of the offer
    energyAmount - the amount of energy (tokens) buyer is buying
    */
    function BuyEnergyFromOffer(uint256 offerId, uint256 energyAmount) public payable {
        require(ep.IsRegistered(msg.sender), "Only registered user (meter) may buy energy from offers");
        require(offers[offerId].exists , "No offer with given ID." );
        require(block.timestamp <= offers[offerId].validUntil, "Offer expired.");
        require(energyAmount <= offers[offerId].energyAmount, "Not enough energy in the offer");
        require(msg.value >= energyAmount*offers[offerId].pricePerEnergyAmount, "Not enough money sent to buy energy");
        //send money to seller
        offers[offerId].sellerAddress.transfer(msg.value);
        offers[offerId].energyAmount -= energyAmount;
        ep.transfer(msg.sender, energyAmount);
        
        if(offers[offerId].energyAmount == 0)
            emit OfferClosed(offerId);
        else 
            emit OfferModified(offerId, offers[offerId].sellerAddress, offers[offerId].validUntil, offers[offerId].pricePerEnergyAmount, offers[offerId].energyAmount);
    }

    /* Method used by energy sellers to modify their existing offers. Fires OfferModified event.
       
    NOTE: Before modifying an offer, for security reasons, the seller must
    authorize this smart contract to transfer tokens in seller's name using increaseAllowance method of ERC20 token accordingly.

    Params:
    offerId - unique id of the offer
    validUntil - new Unix timestamp that marks the time when the offer ends
    pricePerEnergyAmount - new price, in Wei, for every unit of energy being sold
    energyAmount - new amount of energy (tokens) for sell
    */
    function ModifyOffer(uint256 offerId, uint validUntil, uint pricePerEnergyAmount, uint256 energyAmount) public {
        //require(ep.IsRegistered(msg.sender), "Only registered user (meter) may buy energy from offers");
        require(msg.sender == offers[offerId].sellerAddress, "Only creator of the offer can modify it."); //implicitly checks if caller is registered
        require(offers[offerId].validUntil>= block.timestamp, "The offer must be active.");
        require(validUntil > block.timestamp,"Offer deadline must be in the future.");
        require(energyAmount < offers[offerId].energyAmount || energyAmount <= offers[offerId].energyAmount + ep.balanceOf(msg.sender), "Invalid energy amount");
        require(energyAmount <= ep.allowance(msg.sender, address(this)), "Not enough allowance");
        offers[offerId].energyAmount = energyAmount;
        offers[offerId].validUntil = validUntil;
        offers[offerId].pricePerEnergyAmount = pricePerEnergyAmount;
        emit OfferCreated(offerId, offers[offerId].sellerAddress , offers[offerId].validUntil, offers[offerId].pricePerEnergyAmount, offers[offerId].energyAmount);
    }

    /* Method used by energy sellers to retrieve their tokens from the smart contract after the offer expires.
       
    NOTE: Tokens can be recovered only from expired offers.

    Params:
    offerId - unique id of the offer
    */
    function RetrieveTokens(uint256 offerId) public {
        require(offers[offerId].exists , "No offer with given ID." );
        require(msg.sender == offers[offerId].sellerAddress, "Only creator of the offer can retrieve tokens."); //implicitly checks if caller is registered
        require(offers[offerId].validUntil< block.timestamp, "The offer is still active.");
        require(offers[offerId].energyAmount>0, "No tokens the retrieve, the offer was already closed.");
        ep.transfer(msg.sender, offers[offerId].energyAmount );
        offers[offerId].energyAmount = 0;

    }

    /* Method used to list ids of all active energy offers.
       
    NOTE: This function costs gas only when called by another contract.

    Returns:
    Array of uint256 containing ids of offers.
    */
    function ListOffers() public view returns (uint256[] memory){
        uint256[] memory validOffers;
        uint256 size = 0;
        for (uint256 i=1; i<=currentId; i++) {
            if(offers[i].exists && offers[i].validUntil > block.timestamp && offers[i].energyAmount != 0) {
                size++;
            }
                
        }

        uint256 j=0;
        validOffers = new uint256[](size);

        for (uint256 i=1; i<=currentId; i++) {
            if(offers[i].exists && offers[i].validUntil > block.timestamp && offers[i].energyAmount != 0) {
                validOffers[j] = i;
                j++;
            }
        }
        return validOffers;
    }

    /* Method used to get details for specific energy offer.
    
    NOTE: This function costs gas only when called by another contract.
    
    Params:
    offerId - unique id of the offer
    
    Returns:
    address of seller, the amount of energy for sell, expiration of the offer, price (in Wei) per unit of energy
    */
    function GetOfferDetails(uint256 offerId) public view returns (address, uint256, uint256, uint256){
        require(offers[offerId].exists , "No offer with given ID.");
        //require(offers[offerId].validUntil>= block.timestamp, "The offer expired");
        //require(offers[offerId].energyAmount !=0, "The offer is closed");
        return (
            offers[offerId].sellerAddress, 
            offers[offerId].energyAmount,
            offers[offerId].validUntil,
            offers[offerId].pricePerEnergyAmount);
    }

    //WARNING:selfdestruct is deprecated, and will probably change functionality and break the contract in the future
    function deleteContractFullReturn() external {
        require(owner == msg.sender, "Not an owner");
        for (uint256 i=1; i<=currentId; i++) {
            if(offers[i].exists && offers[i].energyAmount != 0) {
                //return all tokens to their original owners
                ep.transfer(offers[i].sellerAddress, offers[i].energyAmount );
            }
                
        }
        selfdestruct(payable(msg.sender));
    }

    //WARNING:selfdestruct is deprecated, and will probably change functionality and break the contract in the future
    function deleteContractOwnerReturn() external {
        require(owner == msg.sender, "Not an owner");
        ep.transfer(owner, ep.balanceOf(address(this)));
        selfdestruct(payable(msg.sender));
    }
}