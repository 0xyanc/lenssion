# Lenssion
Lenssion is combining ERC-6551 (Token Bound Accounts) and ERC-4337 (Account Abstraction) and many more to give NFTs their own, separate history.

For example, NFTs having their own wallets unlocks use cases in gaming where characters would collect weapons, armors, loot during their lives and the owner of the character NFT would easily trade all of the inventory associated with the character.

Built during EthGlobal Lisbon 2023

## Public Good with Account Abstraction on Polygon
The UX optimization strategy I chose was to enable signless transactions (a.k.a. session keys) for users on Lens. 

1) Instead of hashing then signing the UserOp, the frontend will make the user sign a message (ideally using EIP-712 so they know what they are signing) that will act as the session key until revoked. This signature will be passed into all future UserOps so that no more signing is required from the user.

https://github.com/0xyanc/lenssion-client/blob/main/pages/index.js L190-223

2) On the smart contract side, instead of checking the against the UserOp hash as done with the SimpleAccount, the smart contract verifies the signature against EIP-712 and data stored in there (i.e. a string _allowedFunctions_ and a _sessionNonce_). This part was not fully functional but code was left in comments to keep the progress on the verification part.

https://github.com/0xyanc/lenssion/blob/main/src/Account.sol L296-415

3) Some variables are stored in the smart contract to allow the signature verification. A hash is rebuilt using those info and check against the provided signature. Users have the ability to revoke the session key thanks to the _sessionNonce_ integration in the EIP-712 domain specification. They can increment the _sessionNonce_ to invalidate a session key that previously signed.

https://github.com/0xyanc/lenssion/blob/main/src/Account.sol L45-57

## Build #onPolygon in Public Pool Prize
https://twitter.com/0xyanc/status/1657605048552022016
https://mumbai.polygonscan.com/address/0x955303d4d6e30D8844862A8b070c5f83561f5Ff7
https://mumbai.polygonscan.com/address/0x269BE277E5bd92aAbE4A194692D0737C15232823

## Frontend
https://github.com/0xyanc/lenssion-client

