# Lenssion
Lenssion is combining ERC-6551 (Token Bound Accounts) and ERC-4337 (Account Abstraction) and many more to give NFTs their own, separate history.

For example, NFTs having their own wallets unlocks use cases in gaming where characters would collect weapons, armors, loot during their lives and the owner of the character NFT would easily trade all of the inventory associated with the character.

Built during EthGlobal Lisbon 2023

## Public Good with Account Abstraction on Polygon
The UX optimization strategy I chose was to enable signless transactions (a.k.a. session keys) for users on Lens. 

Instead of hashing then signing the UserOp, the frontend will make the user sign a message (ideally using EIP-712 so they know what they are signing) that will act as the session key until revoked. This signature will be passed into all future UserOps so that no more signing is required from the user.

On the smart contract side, instead of checking the against the UserOp hash as done with the SimpleAccount, the smart contract verifies the signature against EIP-712 and data stored in there (i.e. a string _allowedFunctions_ and a _sessionNonce_).

## Frontend
https://github.com/0xyanc/lenssion-client

