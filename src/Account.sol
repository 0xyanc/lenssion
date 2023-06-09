// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "erc6551/interfaces/IERC6551Account.sol";
import "erc6551/lib/ERC6551AccountLib.sol";

import "openzeppelin-contracts/utils/cryptography/ECDSA.sol";
import "openzeppelin-contracts/utils/introspection/IERC165.sol";
import "openzeppelin-contracts/token/ERC721/IERC721.sol";
import "openzeppelin-contracts/token/ERC721/IERC721Receiver.sol";
import "openzeppelin-contracts/token/ERC1155/IERC1155Receiver.sol";
import "openzeppelin-contracts/interfaces/IERC1271.sol";
import "openzeppelin-contracts/utils/cryptography/SignatureChecker.sol";
import "openzeppelin-contracts/proxy/utils/UUPSUpgradeable.sol";

import {BaseAccount as BaseERC4337Account, IEntryPoint, UserOperation} from "account-abstraction/core/BaseAccount.sol";

error NotAuthorized();
error InvalidInput();
error AccountLocked();
error ExceedsMaxLockTime();
error UntrustedImplementation();
error OwnershipCycle();

/**
 * @title A smart contract account owned by a single ERC721 token
 */
contract Account is
    IERC165,
    IERC1271,
    IERC6551Account,
    IERC721Receiver,
    IERC1155Receiver,
    UUPSUpgradeable,
    BaseERC4337Account
{
    using ECDSA for bytes32;

    struct Session {
        address from;
        string allowedFunctions;
        uint256 sessionNonce;
    }

    string private constant SESSION_TYPE =
        "Session(address from,string allowedFunctions,uint256 sessionNonce)";
    uint256 constant chainId = 30001;
    // address constant verifyingContract = ;
    string private constant EIP712_DOMAIN =
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)";

    /// @dev ERC-4337 entry point address
    address public immutable _entryPoint;
    // /// @dev session nonce to check signature against
    uint256 public sessionNonce;
    // /// @dev allowed signless functions during the session
    // string public allowedFunctions = "post,comment,mirror";

    /// @dev mapping from owner => selector => implementation
    mapping(address => mapping(bytes4 => address)) public overrides;

    /// @dev mapping from owner => caller => has permissions
    mapping(address => mapping(address => bool)) public permissions;

    event OverrideUpdated(
        address owner,
        bytes4 selector,
        address implementation
    );

    /// @dev reverts if caller is not the owner of the account
    modifier onlyOwner() {
        if (msg.sender != owner()) revert NotAuthorized();
        _;
    }

    /// @dev reverts if caller is not authorized to execute on this account
    modifier onlyAuthorized() {
        if (!isAuthorized(msg.sender)) revert NotAuthorized();
        _;
    }

    constructor(address entryPoint_) {
        if (entryPoint_ == address(0)) revert InvalidInput();

        _entryPoint = entryPoint_;
    }

    /// @dev allows eth transfers by default, but allows account owner to override
    receive() external payable {
        _handleOverride();
    }

    /// @dev allows account owner to add additional functions to the account via an override
    fallback() external payable {
        _handleOverride();
    }

    /// @dev executes a low-level call against an account if the caller is authorized to make calls
    function executeCall(
        address to,
        uint256 value,
        bytes calldata data
    ) external payable onlyAuthorized returns (bytes memory) {
        emit TransactionExecuted(to, value, data);

        _incrementNonce();

        return _call(to, value, data);
    }

    /// @dev sets the implementation address for a given function call
    function setOverrides(
        bytes4[] calldata selectors,
        address[] calldata implementations
    ) external {
        address _owner = owner();
        if (msg.sender != _owner) revert NotAuthorized();

        uint256 length = selectors.length;

        if (implementations.length != length) revert InvalidInput();

        for (uint256 i = 0; i < length; i++) {
            overrides[_owner][selectors[i]] = implementations[i];
            emit OverrideUpdated(_owner, selectors[i], implementations[i]);
        }

        _incrementNonce();
    }

    /// @dev EIP-1271 signature validation. By default, only the owner of the account is permissioned to sign.
    /// This function can be overriden.
    function isValidSignature(
        bytes32 hash,
        bytes memory signature
    ) external view returns (bytes4 magicValue) {
        _handleOverrideStatic();
        bool isValid = SignatureChecker.isValidSignatureNow(
            owner(),
            hash,
            signature
        );

        if (isValid) {
            return IERC1271.isValidSignature.selector;
        }

        return "";
    }

    /// @dev Returns the EIP-155 chain ID, token contract address, and token ID for the token that
    /// owns this account.
    function token()
        external
        view
        returns (uint256 chainId, address tokenContract, uint256 tokenId)
    {
        return ERC6551AccountLib.token();
    }

    /// @dev End the session by incrementing the sessionNonce
    function endSession() external {
        sessionNonce = sessionNonce + 1;
    }

    /// @dev Returns the current account nonce
    function nonce() public view override returns (uint256) {
        return IEntryPoint(_entryPoint).getNonce(address(this), 0);
    }

    /// @dev Increments the account nonce if the caller is not the ERC-4337 entry point
    function _incrementNonce() internal {
        if (msg.sender != _entryPoint)
            IEntryPoint(_entryPoint).incrementNonce(0);
    }

    /// @dev Return the ERC-4337 entry point address
    function entryPoint() public view override returns (IEntryPoint) {
        return IEntryPoint(_entryPoint);
    }

    /// @dev Returns the owner of the ERC-721 token which owns this account. By default, the owner
    /// of the token has full permissions on the account.
    function owner() public view returns (address) {
        (
            uint256 chainId,
            address tokenContract,
            uint256 tokenId
        ) = ERC6551AccountLib.token();

        if (chainId != block.chainid) return address(0);

        return IERC721(tokenContract).ownerOf(tokenId);
    }

    /// @dev Returns the authorization status for a given caller
    function isAuthorized(address caller) public view returns (bool) {
        // authorize entrypoint for 4337 transactions
        if (caller == _entryPoint) return true;

        (
            uint256 chainId,
            address tokenContract,
            uint256 tokenId
        ) = ERC6551AccountLib.token();
        address _owner = IERC721(tokenContract).ownerOf(tokenId);

        // authorize token owner
        if (caller == _owner) return true;

        // authorize caller if owner has granted permissions
        if (permissions[_owner][caller]) return true;

        return false;
    }

    /// @dev Returns true if a given interfaceId is supported by this account. This method can be
    /// extended by an override.
    function supportsInterface(
        bytes4 interfaceId
    ) public view override returns (bool) {
        bool defaultSupport = interfaceId == type(IERC165).interfaceId ||
            interfaceId == type(IERC1155Receiver).interfaceId ||
            interfaceId == type(IERC6551Account).interfaceId;

        if (defaultSupport) return true;

        // if not supported by default, check override
        _handleOverrideStatic();

        return false;
    }

    /// @dev Allows ERC-721 tokens to be received so long as they do not cause an ownership cycle.
    /// This function can be overriden.
    function onERC721Received(
        address,
        address,
        uint256 receivedTokenId,
        bytes memory
    ) public view override returns (bytes4) {
        _handleOverrideStatic();

        (
            uint256 chainId,
            address tokenContract,
            uint256 tokenId
        ) = ERC6551AccountLib.token();

        if (
            chainId == block.chainid &&
            tokenContract == msg.sender &&
            tokenId == receivedTokenId
        ) revert OwnershipCycle();

        return this.onERC721Received.selector;
    }

    /// @dev Allows ERC-1155 tokens to be received. This function can be overriden.
    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes memory
    ) public view override returns (bytes4) {
        _handleOverrideStatic();

        return this.onERC1155Received.selector;
    }

    /// @dev Allows ERC-1155 token batches to be received. This function can be overriden.
    function onERC1155BatchReceived(
        address,
        address,
        uint256[] memory,
        uint256[] memory,
        bytes memory
    ) public view override returns (bytes4) {
        _handleOverrideStatic();

        return this.onERC1155BatchReceived.selector;
    }

    /// @dev Contract upgrades can only be performed by the owner and the new implementation must
    /// be trusted
    function _authorizeUpgrade(
        address newImplementation
    ) internal view override onlyOwner {
        address _owner = owner();
        if (msg.sender != _owner) revert NotAuthorized();
        revert UntrustedImplementation();
    }

    // function checkSig(
    //     bytes memory signature
    // ) external view returns (uint256 validationData) {
    //     string[3] memory functions = allowedFunctions;
    //     bytes32 messageHashSigned = hashSessionSigned(
    //         msg.sender,
    //         functions,
    //         sessionNonce
    //     );

    //     bool isUserOpValid = recoverSigner(messageHashSigned, signature) ==
    //         owner();
    //     if (!isUserOpValid) {
    //         return 0;
    //     }
    //     return 1;
    // }

    /// @dev Validates a signature for a given ERC-4337 operation
    function _validateSignature(
        UserOperation calldata userOp,
        bytes32 userOpHash
    ) internal view override returns (uint256 validationData) {
        bool isValid = this.isValidSignature(
            userOpHash.toEthSignedMessageHash(),
            userOp.signature
        ) == IERC1271.isValidSignature.selector;

        if (isValid) {
            return 0;
        }

        return 1;
        // string memory functions = allowedFunctions;
        // bytes32 messageHashSigned = hashSessionSigned(
        //     userOp.sender,
        //     functions,
        //     sessionNonce
        // );

        // bool isUserOpValid = recoverSigner(
        //     messageHashSigned,
        //     userOp.signature
        // ) == owner();
        // bool isHashValid = this.isValidSignature(
        //     userOpHash.toEthSignedMessageHash(),
        //     userOp.signature
        // ) == IERC1271.isValidSignature.selector;

        // if (!isUserOpValid || !isHashValid) {
        //     return 0;
        // }
        // return 1;
    }

    // function recoverSigner(
    //     bytes32 _ethSignedMessageHash,
    //     bytes memory _signature
    // ) private pure returns (address) {
    //     (bytes32 r, bytes32 s, uint8 v) = splitSignature(_signature);

    //     return ecrecover(_ethSignedMessageHash, v, r, s);
    // }

    // function splitSignature(
    //     bytes memory sig
    // ) private pure returns (bytes32 r, bytes32 s, uint8 v) {
    //     require(sig.length == 65, "invalid signature length");

    //     assembly {
    //         /*
    //         First 32 bytes stores the length of the signature

    //         add(sig, 32) = pointer of sig + 32
    //         effectively, skips first 32 bytes of signature

    //         mload(p) loads next 32 bytes starting at the memory address p into memory
    //         */

    //         // first 32 bytes, after the length prefix
    //         r := mload(add(sig, 32))
    //         // second 32 bytes
    //         s := mload(add(sig, 64))
    //         // final byte (first byte of the next 32 bytes)
    //         v := byte(0, mload(add(sig, 96)))
    //     }

    //     // implicitly return (r, s, v)
    // }

    // function hashSessionSigned(
    //     address _from,
    //     string[3] memory _allowedFunctions,
    //     uint256 _sessionNonce
    // ) private view returns (bytes32) {
    //     bytes32 DOMAIN_SEPARATOR = keccak256(
    //         abi.encode(
    //             EIP712_DOMAIN,
    //             keccak256("Lenssion"),
    //             keccak256("1"),
    //             chainId,
    //             address(this)
    //         )
    //     );
    //     return
    //         keccak256(
    //             abi.encodePacked(
    //                 "\\x19\\x01",
    //                 DOMAIN_SEPARATOR,
    //                 keccak256(
    //                     abi.encode(
    //                         SESSION_TYPE,
    //                         _from,
    //                         _allowedFunctions,
    //                         _sessionNonce
    //                     )
    //                 )
    //             )
    //         );
    // }

    /// @dev Executes a low-level call
    function _call(
        address to,
        uint256 value,
        bytes calldata data
    ) internal returns (bytes memory result) {
        bool success;
        (success, result) = to.call{value: value}(data);

        if (!success) {
            assembly {
                revert(add(result, 32), mload(result))
            }
        }
    }

    /// @dev Executes a low-level call to the implementation if an override is set
    function _handleOverride() internal {
        address implementation = overrides[owner()][msg.sig];

        if (implementation != address(0)) {
            bytes memory result = _call(implementation, msg.value, msg.data);
            assembly {
                return(add(result, 32), mload(result))
            }
        }
    }

    /// @dev Executes a low-level static call
    function _callStatic(
        address to,
        bytes calldata data
    ) internal view returns (bytes memory result) {
        bool success;
        (success, result) = to.staticcall(data);

        if (!success) {
            assembly {
                revert(add(result, 32), mload(result))
            }
        }
    }

    /// @dev Executes a low-level static call to the implementation if an override is set
    function _handleOverrideStatic() internal view {
        address implementation = overrides[owner()][msg.sig];

        if (implementation != address(0)) {
            bytes memory result = _callStatic(implementation, msg.data);
            assembly {
                return(add(result, 32), mload(result))
            }
        }
    }
}
