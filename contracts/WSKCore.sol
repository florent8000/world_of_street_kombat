
// "SPDX-License-Identifier: UNLICENSED"

pragma solidity 0.8.0;

import "./WSKMinting.sol";

/// @title World Of Street Kombat: Collectible, fightable to the death (not really), play-to-earn on the blockchain.
/// @dev The main World Of Street Kombat contract, keeps track of fighters so they don't wander around and get lost.
contract WSKCore is WSKMinting {

    // This is the main World Of Street Kombat contract. In order to keep our code seperated into logical sections,
    // we've broken it up into multiple files using inheritence, one for each major
    // facet of functionality of WSK. This allows us to keep related code bundled together while still
    // avoiding a single giant file with everything in it. The breakdown is as follows:
    //
    //      - WSKBase: This is where we define the most fundamental code shared throughout the core
    //             functionality. This includes our main data storage, constants and data types, plus
    //             internal functions for managing these items.
    //
    //      - WSKAccessControl: This contract manages the various addresses and constraints for operations
    //             that can be executed only by specific roles. Namely CEO, CFO and COO.
    //
    //      - WSKOwnership: This provides the methods required for basic non-fungible token
    //             transactions, following the draft ERC-721 spec (https://github.com/ethereum/EIPs/issues/721).
    //
    //      - WSKFighting: This file contains the methods necessary to fight warriors together.
    //
    //      - WSKMinting: This final facet contains the functionality we use for creating new gen0 fighters.
    //             We can make up to 5000 "promo" fighters that can be given away (especially important when
    //             the community is new), and all others can only be created and then immediately put up
    //             for sale. Regardless of how they are created, there is a hard limit of 50k gen0 fighters. 
    //             After that, it's all up to the community to fight their way though to unlock new fighters!
    //             
    // 
    // INHERITANCE:
    //       - contract WSKAccessControl 
    //       - contract WSKBase is WSKAccessControl
    //       - contract WSKOwnership is WSKBase, ERC721
    //       - contract WSKFighting is WSKOwnership
    //       - contract WSKMinting is WSKFighting
    //       - contract WSKCore is WSKMinting

    //  Set in case the core contract is broken and an upgrade is required
    address public newContractAddress;

    /// @notice Creates the main World Of Street Kombat smart contract instance.
    function WSKCore() public {
        // Starts paused.
        paused = true;

        // the creator of the contract is the initial CEO
        ceoAddress = msg.sender;

        // the creator of the contract is also the initial COO
        cooAddress = msg.sender;

        // start with the mythical fighter 0
        _createFighter(0, 0, 0, uint256(-1), address(0));
    }

    /// @dev Used to mark the smart contract as upgraded, in case there is a serious
    ///  breaking bug. This method does nothing but keep track of the new contract and
    ///  emit a message indicating that the new address is set. It's up to clients of this
    ///  contract to update to the new contract address in that case. (This contract will
    ///  be paused indefinitely if such an upgrade takes place.)
    /// @param _v2Address new address
    function setNewAddress(address _v2Address) external onlyCEO whenPaused {
        newContractAddress = _v2Address;
        ContractUpgrade(_v2Address);
    }

    /// @notice Returns all the relevant information about a specific fighter.
    /// @param _id The ID of the fighter of interest.
    function getFighter(uint256 _id)
        external
        view
        returns (
        uint256 genes,
        uint64 level,
        uint64 experience,
        uint64 victories,
        uint64 defeats,
        uint32 agility,
        uint32 speed,
        uint32 strengh
    ) {
        Fighter storage fight = fighters[_id];

        // todo - add isInHospital and weapons
        genes = fight.genes;
        level = fight.level;
        experience = fight.experience;
        victories = fight.victories;
        defeats = fight.defeats;
        agility = fight.agility;
        speed = fight.speed;
        strengh = fight.strengh;
    }
    }

    /// @dev Override unpause so it requires the newContractAddress not to be set either, 
    /// (we want to keep the contract paused if it was upgraded)
    /// @notice This is public rather than external so we can call super.unpause
    ///  without using an expensive CALL.
    function unpause() public onlyCEO whenPaused {
        require(newContractAddress == address(0));

        // Actually unpause the contract.
        super.unpause();
    }

    // @dev Allows the CFO to capture the balance available to the contract.
    function withdrawBalance() external onlyCFO {
        uint256 balance = this.balance;
        cfoAddress.send(balance);
    }
}