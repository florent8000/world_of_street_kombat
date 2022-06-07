// "SPDX-License-Identifier: UNLICENSED"

pragma solidity 0.8.0;

import "./WSKBase.sol";
import "./ERC721Metadata.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

///  World of Street Kombat org
/*
INHERITANCE:
    contract WSKAccessControl 
    contract WSKBase is WSKAccessControl
    contract WSKOwnership is WSKBase, ERC721
    contract WSKMinting is WSKOwnership
    contract WSKCore is WSKMinting

DEFINITIONS:
    contract WSKAccessControl - This is for management control. The code has special roles, e.g. ’CEO‘, ’COO‘, and ’CFO‘.
                                 This contract defines a few functions for these roles only.
    contract WSKBase  - This accomplishes multiple tasks. It specifies attributes for fighters, e.g. characteristics, 
                        genetic code, etc. This contract also serves as a database for all fighters and their ownership.
    contract WSKOwnership - This contract defines kittens as crypto tokens. These tokens follow ERC721 standards
    contract WSKMinting - This is the contract for creating ’gen 0‘ fighters. These will be the new fighters to get 
                            the game started. There is a hard limit of 50,000 such fighters.
    contract WSKCore - The main smart contract that combines everything together
*/

/// @title The facet of the Wolrd Of Street Kombat core contract that manages ownership, ERC-721 compliant.
contract WSKOwnership is WSKBase, ERC721 {
    /// @notice Name and symbol of the non fungible token, as defined in ERC721.
    string public constant name = "WolrdOfStreetKombat";
    string public constant symbol = "WSK";

    // The contract that will return fighter metadata
    ERC721Metadata public erc721Metadata;

    /// @dev Set the address of the sibling contract that tracks metadata.
    ///  CEO only.
    function setMetadataAddress(address _contractAddress) public onlyCEO {
        erc721Metadata = ERC721Metadata(_contractAddress);
    }

    // Internal utility functions: These functions all assume that their input arguments
    // are valid. We leave it to public methods to sanitize their inputs and follow
    // the required logic.

    /// @dev Checks if a given address is the current owner of a particular Fighter.
    /// @param _claimant the address we are validating against.
    /// @param _tokenId fighter id, only valid when > 0
    function _owns(address _claimant, uint256 _tokenId)
        internal
        view
        returns (bool)
    {
        return fighterIndexToOwner[_tokenId] == _claimant;
    }

    /// @dev Checks if a given address currently has transferApproval for a particular Fighter.
    /// @param _claimant the address we are confirming fighter is approved for.
    /// @param _tokenId fighter id, only valid when > 0
    function _approvedFor(address _claimant, uint256 _tokenId)
        internal
        view
        returns (bool)
    {
        return fighterIndexToApproved[_tokenId] == _claimant;
    }

    /// @dev Marks an address as being approved for transferFrom(), overwriting any previous
    ///  approval. Setting _approved to address(0) clears all transfer approval.
    ///  NOTE: _approve() does NOT send the Approval event. This is intentional because
    ///  _approve() and transferFrom() are used together for putting fighters on auction, and
    ///  there is no value in spamming the log with Approval events in that case.
    function _approve(uint256 _tokenId, address _approved) internal {
        fighterIndexToApproved[_tokenId] = _approved;
    }

    /// @notice Returns the number of fighters owned by a specific address.
    /// @param _owner The owner address to check.
    /// @dev Required for ERC-721 compliance
    function balanceOf(address _owner) public view returns (uint256 count) {
        return ownershipTokenCount[_owner];
    }

    /// @notice Transfers a Fighter to another address. If transferring to a smart
    ///  contract be VERY CAREFUL to ensure that it is aware of ERC-721 (or
    ///  Wolrd Of Street Kombat specifically) or your Fighter may be lost forever. Seriously.
    /// @param _to The address of the recipient, can be a user or contract.
    /// @param _tokenId The ID of the Fighter to transfer.
    /// @dev Required for ERC-721 compliance.
    function transfer(address _to, uint256 _tokenId) external whenNotPaused {
        // Safety check to prevent against an unexpected 0x0 default.
        require(_to != address(0));
        // Disallow transfers to this contract to prevent accidental misuse.
        // The contract should never own any fighters (except very briefly
        // after a gen0 cat is created and before it goes on auction).
        require(_to != address(this));
        // Disallow transfers to the auction contracts to prevent accidental
        // misuse. Auction contracts should only take ownership of fighters
        // through the allow + transferFrom flow.
        require(_to != address(saleAuction));
        require(_to != address(siringAuction));

        // You can only send your own cat.
        require(_owns(msg.sender, _tokenId));

        // Reassign ownership, clear pending approvals, emit Transfer event.
        _transfer(msg.sender, _to, _tokenId);
    }

    /// @notice Grant another address the right to transfer a specific Fighter via
    ///  transferFrom(). This is the preferred flow for transfering NFTs to contracts.
    /// @param _to The address to be granted transfer approval. Pass address(0) to
    ///  clear all approvals.
    /// @param _tokenId The ID of the Fighter that can be transferred if this call succeeds.
    /// @dev Required for ERC-721 compliance.
    function approve(address _to, uint256 _tokenId) external whenNotPaused {
        // Only an owner can grant transfer approval.
        require(_owns(msg.sender, _tokenId));

        // Register the approval (replacing any previous approval).
        _approve(_tokenId, _to);

        // Emit approval event.
        Approval(msg.sender, _to, _tokenId);
    }

    /// @notice Transfer a Fighter owned by another address, for which the calling address
    ///  has previously been granted transfer approval by the owner.
    /// @param _from The address that owns the Fighter to be transfered.
    /// @param _to The address that should take ownership of the Fighter. Can be any address,
    ///  including the caller.
    /// @param _tokenId The ID of the Fighter to be transferred.
    /// @dev Required for ERC-721 compliance.
    function transferFrom(
        address _from,
        address _to,
        uint256 _tokenId
    ) external whenNotPaused {
        // Safety check to prevent against an unexpected 0x0 default.
        require(_to != address(0));
        // Disallow transfers to this contract to prevent accidental misuse.
        // The contract should never own any fighters (except very briefly
        // after a gen0 cat is created and before it goes on auction).
        require(_to != address(this));
        // Check for approval and valid ownership
        require(_approvedFor(msg.sender, _tokenId));
        require(_owns(_from, _tokenId));

        // Reassign ownership (also clears pending approvals and emits Transfer event).
        _transfer(_from, _to, _tokenId);
    }

    /// @notice Returns the total number of fighters currently in existence.
    /// @dev Required for ERC-721 compliance.
    function totalSupply() public view returns (uint256) {
        return fighters.length - 1;
    }

    /// @notice Returns the address currently assigned ownership of a given Fighter.
    /// @dev Required for ERC-721 compliance.
    function ownerOf(uint256 _tokenId) external view returns (address owner) {
        owner = kittyIndexToOwner[_tokenId];

        require(owner != address(0));
    }

    /// @notice Returns a list of all Fighter IDs assigned to an address.
    /// @param _owner The owner whose fighters we are interested in.
    /// @dev This method MUST NEVER be called by smart contract code. First, it's fairly
    ///  expensive (it walks the entire Fighter array looking for cats belonging to owner),
    ///  but it also returns a dynamic array, which is only supported for web3 calls, and
    ///  not contract-to-contract calls.
    function tokensOfOwner(address _owner)
        external
        view
        returns (uint256[] ownerTokens)
    {
        uint256 tokenCount = balanceOf(_owner);

        if (tokenCount == 0) {
            // Return an empty array
            return new uint256[](0);
        } else {
            uint256[] memory result = new uint256[](tokenCount);
            uint256 totalCats = totalSupply();
            uint256 resultIndex = 0;

            // We count on the fact that all cats have IDs starting at 1 and increasing
            // sequentially up to the totalCat count.
            uint256 IDFighter;

            for (IDFighter = 1; IDFighter <= totalCats; IDFighter++) {
                if (kittyIndexToOwner[IDFighter] == _owner) {
                    result[resultIndex] = IDFighter;
                    resultIndex++;
                }
            }

            return result;
        }
    }

    /// @dev Adapted from memcpy() by @arachnid (Nick Johnson <arachnid@notdot.net>)
    ///  This method is licenced under the Apache License.
    ///  Ref: https://github.com/Arachnid/solidity-stringutils/blob/2f6ca9accb48ae14c66f1437ec50ed19a0616f78/strings.sol
    function _memcpy(
        uint256 _dest,
        uint256 _src,
        uint256 _len
    ) private view {
        // Copy word-length chunks while possible
        for (; _len >= 32; _len -= 32) {
            assembly {
                mstore(_dest, mload(_src))
            }
            _dest += 32;
            _src += 32;
        }

        // Copy remaining bytes
        uint256 mask = 256**(32 - _len) - 1;
        assembly {
            let srcpart := and(mload(_src), not(mask))
            let destpart := and(mload(_dest), mask)
            mstore(_dest, or(destpart, srcpart))
        }
    }

    /// @dev Adapted from toString(slice) by @arachnid (Nick Johnson <arachnid@notdot.net>)
    ///  This method is licenced under the Apache License.
    ///  Ref: https://github.com/Arachnid/solidity-stringutils/blob/2f6ca9accb48ae14c66f1437ec50ed19a0616f78/strings.sol
    function _toString(bytes32[4] _rawBytes, uint256 _stringLength)
        private
        view
        returns (string)
    {
        string outputString = new string(_stringLength);
        uint256 outputPtr;
        uint256 bytesPtr;

        assembly {
            outputPtr := add(outputString, 32)
            bytesPtr := _rawBytes
        }

        _memcpy(outputPtr, bytesPtr, _stringLength);

        return outputString;
    }

    /// @notice Returns a URI pointing to a metadata package for this token conforming to
    ///  ERC-721 (https://github.com/ethereum/EIPs/issues/721)
    /// @param _tokenId The ID number of the Fighter whose metadata should be returned.
    function tokenMetadata(uint256 _tokenId, string _preferredTransport)
        external
        view
        returns (string infoUrl)
    {
        require(erc721Metadata != address(0));
        bytes32[4] memory buffer;
        uint256 count;
        (buffer, count) = erc721Metadata.getMetadata(
            _tokenId,
            _preferredTransport
        );

        return _toString(buffer, count);
    }
}
