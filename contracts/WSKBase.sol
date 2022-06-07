// "SPDX-License-Identifier: UNLICENSED"

pragma solidity 0.8.0;

import "./WSKAccessControl.sol";

/// @title Base contract for Wolrd of Street Kombat. Holds all common structs, events and base variables.
/// @dev See the WSKCore contract documentation to understand how the various contract facets are arranged.
contract WSKBase is WSKAccessControl {
    /*** EVENTS ***/

    /// @dev The Birth event is fired whenever a new fighter comes into existence.
    event Birth(address owner, uint256 fighterId, uint256 genes);

    /// @dev Transfer event as defined in current draft of ERC721. Emitted every time a fighter
    ///  ownership is assigned, including births.
    event Transfer(address from, address to, uint256 tokenId);

    /*** DATA TYPES ***/

    /// @dev The main Fighter struct. Every fighter in Wolrd of Street Kombat is represented by a copy
    ///  of this structure, so great care was taken to ensure that it fits neatly into
    ///  exactly two 256-bit words. Note that the order of the members in this structure
    ///  is important because of the byte-packing rules used by Ethereum.
    ///  Ref: http://solidity.readthedocs.io/en/develop/miscellaneous.html
    /// TODO - Add weapons
    struct Fighter {
        // The Fighter's genetic code is packed into these 256-bits, the format is
        // sooper-sekret! A fighter's genes never change.
        uint256 genes;
        // The timestamp from the block when this fighter came into existence.
        uint64 level;
        // The level the fighter has reached in the game.
        uint64 experience;
        // The number of fights the fighter has taken part into.
        uint64 victories;
        // The number of fights the fighter has won
        uint64 defeats;
        // The number of fights the fighter has won
        uint32 agility;
        // One of the characteristic of the fighter, agility denotes how easily
        // the fighter can dodge attack from enemies
        uint32 speed;
        // One of the characteristic of the fighter, speed denotes how often
        // the fighter can attack from enemies
        uint32 strengh;
        // One of the characteristic of the fighter, strengh denotes how hard
        // the fighter can hit enemies
    }

    /*** CONSTANTS ***/

    /// @dev A lookup table indicating the cooldown duration after any successful
    ///  breeding action, called "pregnancy time" for matrons and "siring cooldown"
    ///  for sires. Designed such that the cooldown roughly doubles each time a fighter
    ///  is bred, encouraging owners not to just keep breeding the same fighter over
    ///  and over again. Caps out at one week (a fighter can breed an unbounded number
    ///  of times, and the maximum cooldown is always seven days).
    uint32[14] public cooldowns = [
        uint32(1 minutes),
        uint32(2 minutes),
        uint32(5 minutes),
        uint32(10 minutes),
        uint32(30 minutes),
        uint32(1 hours),
        uint32(2 hours),
        uint32(4 hours),
        uint32(8 hours),
        uint32(16 hours),
        uint32(1 days),
        uint32(2 days),
        uint32(4 days),
        uint32(7 days)
    ];

    // An approximation of currently how many seconds are in between blocks.
    uint256 public secondsPerBlock = 15;

    /*** STORAGE ***/

    /// @dev An array containing the Fighter struct for all Kitties in existence. The ID
    ///  of each fighter is actually an index into this array. Note that ID 0 is a negacat,
    ///  the unKitty, the mythical beast that is the parent of all gen0 cats. A bizarre
    ///  creature that is both matron and sire... to itself! Has an invalid genetic code.
    ///  In other words, fighter ID 0 is invalid... ;-)
    Fighter[] fighters;

    /// @dev A mapping from fighter IDs to the address that owns them. All cats have
    ///  some valid owner address, even gen0 cats are created with a non-zero owner.
    mapping(uint256 => address) public kittyIndexToOwner;

    // @dev A mapping from owner address to count of tokens that address owns.
    //  Used internally inside balanceOf() to resolve ownership count.
    mapping(address => uint256) ownershipTokenCount;

    /// @dev A mapping from KittyIDs to an address that has been approved to call
    ///  transferFrom(). Each Fighter can only have one approved address for transfer
    ///  at any time. A zero value means no approval is outstanding.
    mapping(uint256 => address) public kittyIndexToApproved;

    /// @dev A mapping from KittyIDs to an address that has been approved to use
    ///  this Fighter for siring via breedWith(). Each Fighter can only have one approved
    ///  address for siring at any time. A zero value means no approval is outstanding.
    mapping(uint256 => address) public sireAllowedToAddress;

    /// @dev The address of the ClockAuction contract that handles sales of Kitties. This
    ///  same contract handles both peer-to-peer sales as well as the gen0 sales which are
    ///  initiated every 15 minutes.
    SaleClockAuction public saleAuction;

    /// @dev The address of a custom ClockAuction subclassed contract that handles siring
    ///  auctions. Needs to be separate from saleAuction because the actions taken on success
    ///  after a sales and siring auction are quite different.
    SiringClockAuction public siringAuction;

    /// @dev Assigns ownership of a specific Fighter to an address.
    function _transfer(
        address _from,
        address _to,
        uint256 _tokenId
    ) internal {
        // Since the number of fighters is capped to 2^32 we can't overflow this
        ownershipTokenCount[_to]++;
        // transfer ownership
        kittyIndexToOwner[_tokenId] = _to;
        // When creating new fighters _from is 0x0, but we can't account that address.
        if (_from != address(0)) {
            ownershipTokenCount[_from]--;
            // once the fighter is transferred also clear sire allowances
            delete sireAllowedToAddress[_tokenId];
            // clear any previously approved ownership exchange
            delete kittyIndexToApproved[_tokenId];
        }
        // Emit the transfer event.
        Transfer(_from, _to, _tokenId);
    }

    /// @dev An internal method that creates a new fighter and stores it. This
    ///  method doesn't do any checking and should only be called when the
    ///  input data is known to be valid. Will generate both a Birth event
    ///  and a Transfer event.
    /// @param _matronId The fighter ID of the matron of this fighter (zero for gen0)
    /// @param _sireId The fighter ID of the sire of this fighter (zero for gen0)
    /// @param _generation The generation number of this fighter, must be computed by caller.
    /// @param _genes The fighter's genetic code.
    /// @param _owner The inital owner of this fighter, must be non-zero (except for the unKitty, ID 0)
    function _createKitty(
        uint256 _matronId,
        uint256 _sireId,
        uint256 _generation,
        uint256 _genes,
        address _owner
    ) internal returns (uint256) {
        // These requires are not strictly necessary, our calling code should make
        // sure that these conditions are never broken. However! _createKitty() is already
        // an expensive call (for storage), and it doesn't hurt to be especially careful
        // to ensure our data structures are always valid.
        require(_matronId == uint256(uint32(_matronId)));
        require(_sireId == uint256(uint32(_sireId)));
        require(_generation == uint256(uint16(_generation)));

        // New fighter starts with the same cooldown as parent gen/2
        uint16 cooldownIndex = uint16(_generation / 2);
        if (cooldownIndex > 13) {
            cooldownIndex = 13;
        }

        Fighter memory _fighter = Fighter({
            genes: _genes,
            birthTime: uint64(now),
            cooldownEndBlock: 0,
            matronId: uint32(_matronId),
            sireId: uint32(_sireId),
            siringWithId: 0,
            cooldownIndex: cooldownIndex,
            generation: uint16(_generation)
        });
        uint256 newFighterId = kitties.push(_fighter) - 1;

        // It's probably never going to happen, 4 billion cats is A LOT, but
        // let's just be 100% sure we never let this happen.
        require(newFighterId == uint256(uint32(newFighterId)));

        // emit the birth event
        Birth(
            _owner,
            newFighterId,
            uint256(_fighter.matronId),
            uint256(_fighter.sireId),
            _fighter.genes
        );

        // This will assign ownership, and also emit the Transfer event as
        // per ERC721 draft
        _transfer(0, _owner, newFighterId);

        return newFighterId;
    }

    // Any C-level can fix how many seconds per blocks are currently observed.
    function setSecondsPerBlock(uint256 secs) external onlyCLevel {
        require(secs < cooldowns[0]);
        secondsPerBlock = secs;
    }
}
