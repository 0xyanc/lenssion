// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import "openzeppelin-contracts/utils/cryptography/ECDSA.sol";
import "openzeppelin-contracts/interfaces/IERC1271.sol";

contract ERC712 {
    using ECDSA for bytes32;
    bytes32 private immutable _CACHED_DOMAIN_SEPARATOR;
    uint256 private immutable _CACHED_CHAIN_ID;

    bytes32 private immutable _HASHED_NAME;
    bytes32 private immutable _HASHED_VERSION;
    bytes32 private immutable _TYPE_HASH;

    address public owner;
    string public constant allowedFunctions = "post,comment,mirror";
    uint256 sessionNonce;

    constructor() {
        bytes32 hashedName = keccak256(bytes("Lenssion"));
        bytes32 hashedVersion = keccak256(bytes("1"));
        bytes32 typeHash = keccak256(
            "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
        );
        _HASHED_NAME = hashedName;
        _HASHED_VERSION = hashedVersion;
        _CACHED_CHAIN_ID = block.chainid;
        _CACHED_DOMAIN_SEPARATOR = _buildDomainSeparator(
            typeHash,
            hashedName,
            hashedVersion
        );
        _TYPE_HASH = typeHash;
        owner = msg.sender;
    }

    /**
     * @dev Returns the domain separator for the current chain.
     */
    function _domainSeparatorV4() internal view returns (bytes32) {
        if (block.chainid == _CACHED_CHAIN_ID) {
            return _CACHED_DOMAIN_SEPARATOR;
        } else {
            return
                _buildDomainSeparator(
                    _TYPE_HASH,
                    _HASHED_NAME,
                    _HASHED_VERSION
                );
        }
    }

    function _buildDomainSeparator(
        bytes32 typeHash,
        bytes32 name,
        bytes32 version
    ) private view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    typeHash,
                    name,
                    version,
                    block.chainid,
                    address(this)
                )
            );
    }

    /**
     * @dev Given an already https://eips.ethereum.org/EIPS/eip-712#definition-of-hashstruct[hashed struct], this
     * function returns the hash of the fully encoded EIP712 message for this domain.
     *
     * This hash can be used together with {ECDSA-recover} to obtain the signer of a message. For example:
     *
     * ```solidity
     * bytes32 digest = _hashTypedDataV4(keccak256(abi.encode(
     *     keccak256("Mail(address to,string contents)"),
     *     mailTo,
     *     keccak256(bytes(mailContents))
     * )));
     * address signer = ECDSA.recover(digest, signature);
     * ```
     */
    function _hashTypedDataV4(
        bytes32 structHash
    ) internal view virtual returns (bytes32) {
        return
            keccak256(
                abi.encodePacked("\x19\x01", _domainSeparatorV4(), structHash)
            );
    }

    function isValidSignature(
        bytes32 hash,
        bytes memory signature
    ) external view returns (address magicValue) {
        bytes32 digest = _hashTypedDataV4(
            keccak256(
                abi.encode(
                    keccak256(
                        "Session(address from,string allowedFunctions,uint256 sessionNonce)"
                    ),
                    owner,
                    keccak256(bytes(allowedFunctions)),
                    sessionNonce
                )
            )
        );
        address signer = ECDSA.recover(digest, signature);

        if (owner == signer) {
            return owner;
        }

        return signer;
    }
}
