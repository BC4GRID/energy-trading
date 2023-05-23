// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "./ERC20.sol";


struct TradeOffer {
    address payable sellerAddress;
    uint256 energyAmount;
    uint validUntil; //timestamp do kada vazi.
    uint pricePerEnergyAmount; //in Wei
    bool exists; //flag for reading from mapping
}


contract EnergyPool is ERC20 {
    address private owner;
    mapping(address => bool) private isMeterRegistered;

    uint256 private currentId;
    mapping (uint256 => TradeOffer) public offers;

    //event that fires when an offer is created
    event OfferCreated(uint256 id, address seller, uint validUntil, uint pricePerEnergyAmount, uint256 energyAmount);

    //event that fires when some of the electricity
    event OfferModified(uint256 id, address seller, uint validUntil, uint pricePerEnergyAmount, uint256 energyAmount);
    
    //event that fires when offer is closed (sold or expired)
    event OfferClosed(uint256 id);


    constructor() ERC20("EnergyToken", "ENT") {
        owner = msg.sender;
    }

    modifier OnlyOwner() {
        require(msg.sender == owner);
        _;
    }

    //stavljamo da su decimale tokena 2. Tako da ako neko ima 200 tokena to se prikazuje kao 2,00
    function decimals() public view virtual override returns (uint8) {
        return 2;
    }

    //used for registration of smart meters from the microgrid
    function RegisterSmartMeter(address meterAddress) public OnlyOwner returns (bool) {
        require(isMeterRegistered[meterAddress] == false, "Smart meter address already registered");
        isMeterRegistered[meterAddress] = true;
        return true;
    }

    //used for revoking registration of smart meters from the microgrid
    function UnregisterSmartMeter(address meterAddress) public OnlyOwner returns (bool) {
        require(isMeterRegistered[meterAddress], "Smart meter address is not registered");
        isMeterRegistered[meterAddress] = false;
        return true;
    }

    //function called by a smart meter when prosumers fills the pool, energySent should be same decimal as token (2) 1token = 1kwh
    function SendEnergy(uint256 energySent) public {
        require(isMeterRegistered[msg.sender],"The calling address is not registered smart meter");
        require(energySent > 0, "Energy sent to energy pool must be greater than 0.");
        //the meter reports emmited energy, tokens should be sent to that address
        _mint(msg.sender, energySent);
    }

    //function called by a smart meter when prosumer asks for energy from the pool, energyAmount should be same decimal as token (2) 1token = 1kwh
    function ReceiveEnegy(uint256 energyReceived) public {
        require(isMeterRegistered[msg.sender], "The calling address is not registered smart meter");
        require(energyReceived > 0, "Energy taken from the energy pool must be greater than 0.");
        //burn the tokens of the consumer, as he used them to take energy from the pool
        _burn(msg.sender, energyReceived);
    }

    function IsRegistered(address meterAddress) public view returns (bool) {
        return isMeterRegistered[meterAddress];
    }

    function getID() private returns (uint256) {
        currentId++;
        return currentId;
    }

    // a seller creates an offer, price is in Wei
    function CreateEnergyOffer(uint validUntil, uint pricePerEnergyAmount, uint256 energyAmount) public {
        require(IsRegistered(msg.sender), "Only registered user (meter) may make sell offers");
        require(energyAmount <= balanceOf(msg.sender), "Must have tokens to sell.");
        require(validUntil > block.timestamp,"Offer deadline must be in the future.");//TODO: videti koliko u buducnosti, jer block.timestamp nije bas trenutno vreme
        transfer(address(this), energyAmount); //prebaci tokene na ugovor

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
        require(IsRegistered(msg.sender), "Only registered user (meter) may buy energy from offers");
        require(offers[offerId].exists , "No offer with given ID." );
        require(block.timestamp <= offers[offerId].validUntil, "Offer expired.");
        require(energyAmount <= offers[offerId].energyAmount, "Not enough energy in the offer");
        require(msg.value >= energyAmount*offers[offerId].pricePerEnergyAmount, "Not enough money sent to buy energy");
        //send money to seller
        offers[offerId].sellerAddress.transfer(msg.value);
        //update offer
        offers[offerId].energyAmount -= energyAmount;
        //prebaci tokene kupcu sa ugovora
        _transfer(address(this), msg.sender, energyAmount );
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
        _transfer(address(this), msg.sender, offers[offerId].energyAmount );
        offers[offerId].energyAmount = 0;

    }

}

