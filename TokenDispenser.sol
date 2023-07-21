// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "./ERC20.sol";

contract TokenDispenser is ERC20 {
    address private owner;
    mapping(address => bool) private isMeterRegistered;

    
    constructor() ERC20("EnergyToken", "ENT") {
        owner = msg.sender;
    }

    modifier OnlyOwner() {
        require(msg.sender == owner);
        _;
    }

    // the number of decimals is set to 2. For example, a balance of `200` tokens is displayed to a user as `2.00`
    function decimals() public view virtual override returns (uint8) {
        return 2;
    }

    /* Method used to register smart meter.
    
    NOTE: Only the owner of the TokenDispenser contract may register meters.

    Params:
    meterAddress - Ethereum address of smart meter
    */
    function RegisterSmartMeter(address meterAddress) public OnlyOwner returns (bool) {
        require(isMeterRegistered[meterAddress] == false, "Smart meter address already registered");
        isMeterRegistered[meterAddress] = true;
        return true;
    }

    /* Method used to unregister smart meter.
    
    NOTE: Only the owner of the TokenDispenser contract may unregister meters.

    Params:
    meterAddress - Ethereum address of smart meter
    */
    function UnregisterSmartMeter(address meterAddress) public OnlyOwner returns (bool) {
        require(isMeterRegistered[meterAddress], "Smart meter address is not registered");
        isMeterRegistered[meterAddress] = false;
        return true;
    }

    
    /* Method used by prosumers that send energy to the grid. In return, they recieve tokens.
    
    Params:
    energySent - The amount of sent energy
    */

    //function called by a smart meter when prosumers fills the pool, energySent should be same decimal as token (2) 1token = 1kwh
    function SendEnergy(uint256 energySent) public {
        require(isMeterRegistered[msg.sender],"The calling address is not registered smart meter");
        require(energySent > 0, "Energy sent to energy pool must be greater than 0.");
        //the meter reports emmited energy, tokens should be sent to that address
        _mint(msg.sender, energySent);
    }

    /* Method used by consumers to trade tokens for energy. This effectively burns the tokens.
    
    Params:
    energyReceived - The amount of received energy
    */
    function ReceiveEnergy(uint256 energyReceived) public {
        require(isMeterRegistered[msg.sender], "The calling address is not registered smart meter");
        require(energyReceived > 0, "Energy taken from the energy pool must be greater than 0.");
        //burn the tokens of the consumer, as he used them to take energy from the pool
        _burn(msg.sender, energyReceived);
    }

    function IsRegistered(address meterAddress) public view returns (bool) {
        return isMeterRegistered[meterAddress];
    }

    //WARNING:selfdestruct is deprecated, and will probably change functionality and break the contract in the future
    function deleteContract() external {
        require(owner == msg.sender, "Not an owner");
        selfdestruct(payable(msg.sender));
    }
}

