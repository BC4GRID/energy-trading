// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "./tokenDispenser.sol";

struct TradeOffer {
    address payable sellerAddress;
    uint256 energyAmount;
    uint validUntil; //timestamp do kada vazi.
    uint pricePerEnergyAmount; //in Wei
    bool exists; //flag for reading from mapping
}

contract Trading {
    address private owner;
    uint256 private currentId;
    address private epAddress;
    EnergyPool private ep;

    mapping (uint256 => TradeOffer) public offers;

    //event that fires when an offer is created
    event OfferCreated(uint256 id, address seller, uint validUntil, uint pricePerEnergyAmount, uint256 energyAmount);

    //event that fires when some of the electricity
    event OfferModified(uint256 id, address seller, uint validUntil, uint pricePerEnergyAmount, uint256 energyAmount);
    
    //event that fires when offer is closed (sold or expired)
    event OfferClosed(uint256 id);


    function getID() private returns (uint256) {
        currentId++;
        return currentId;
    }

    constructor(address EnergyPoolContractAddress) {
        epAddress = EnergyPoolContractAddress;
        ep = EnergyPool(EnergyPoolContractAddress);
        owner = msg.sender;
    }

    // a seller creates an offer, price is in Wei
    function CreateEnergyOffer(uint validUntil, uint pricePerEnergyAmount, uint256 energyAmount) public {
        require(ep.IsRegistered(msg.sender), "Only registered user (meter) may make sell offers");
        require(energyAmount <= ep.balanceOf(msg.sender), "Must have tokens to sell.");
        require(validUntil > block.timestamp,"Offer deadline must be in the future.");//TODO: videti koliko u buducnosti, jer block.timestamp nije bas trenutno vreme
        //iz bezbednosnih razloga, korisnik mora da pozove approve i da dozvoli da ovaj ugovor radi sa energyAmount tokena koje prebaci sebi na adresu
        //ovo mora da radi eksplicitno da bi sledece radilo!
        require(energyAmount <= ep.allowance(msg.sender, address(this)), "User made no allowance to contract");
        ep.transferFrom(msg.sender, address(this), energyAmount);
        //ep.transfer(address(this), energyAmount); //prebaci tokene na ugovor
        //bytes memory data = abi.encodeWithSignature("_transfer(address, uint256)", msg.sender, energyAmount);

        //(bool success, ) =  epAddress.call(data);
        uint256 id = getID();

        offers[id] = TradeOffer({
            sellerAddress: payable(msg.sender), 
            energyAmount:energyAmount,
            validUntil: validUntil,
            pricePerEnergyAmount: pricePerEnergyAmount,
            exists: true});
        emit OfferCreated(id, msg.sender, validUntil, pricePerEnergyAmount, energyAmount);
    }

    //price is in Wei
    function BuyEnergyFromOffer(uint256 offerId, uint256 energyAmount) public payable {
        require(ep.IsRegistered(msg.sender), "Only registered user (meter) may buy energy from offers");
        require(offers[offerId].exists , "No offer with given ID." );
        require(block.timestamp <= offers[offerId].validUntil, "Offer expired.");
        require(energyAmount <= offers[offerId].energyAmount, "Not enough energy in the offer");
        require(msg.value >= energyAmount*offers[offerId].pricePerEnergyAmount, "Not enough money sent to buy energy");
        //send money to seller
        offers[offerId].sellerAddress.transfer(msg.value);
        //update offer
        offers[offerId].energyAmount -= energyAmount;
        //prebaci tokene kupcu sa ugovora
        //ep._transfer(address(this), msg.sender, energyAmount );
        //bytes memory data = abi.encodeWithSignature("_transfer(address, uint256)", msg.sender, energyAmount);

        //(bool success, ) =  epAddress.call(data);
        ep.transfer(msg.sender, energyAmount);
        
        if(offers[offerId].energyAmount == 0)
            emit OfferClosed(offerId);
        else 
            emit OfferModified(offerId, offers[offerId].sellerAddress, offers[offerId].validUntil, offers[offerId].pricePerEnergyAmount, offers[offerId].energyAmount);
    }

    function RetrieveTokens(uint256 offerId) public {
        require(offers[offerId].exists , "No offer with given ID." );
        require(msg.sender == offers[offerId].sellerAddress, "Only creator of the offer can retrieve tokens."); //implicitly checks if caller is registered
        require(offers[offerId].validUntil>= block.timestamp, "The offer is still active.");
        require(offers[offerId].energyAmount>0, "No tokens the retrieve, the offer was already closed.");
        //ep._transfer(address(this), msg.sender, offers[offerId].energyAmount );
        ep.transfer(msg.sender, offers[offerId].energyAmount );
        offers[offerId].energyAmount = 0;

    }
}