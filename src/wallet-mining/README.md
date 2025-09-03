# Wallet Mining

There’s a contract that incentivizes users to deploy Safe wallets, rewarding them with 1 DVT. It integrates with an upgradeable authorization mechanism, only allowing certain deployers (a.k.a. wards) to be paid for specific deployments.

("copy" stands for the bytecode of the contract to be deployed)
The deployer contract only works with a Safe factory and copy set during deployment. It looks like the [Safe singleton factory](https://github.com/safe-global/safe-singleton-factory) is already deployed.

the deployer contract is the one who deploys the new Safe Wallet. It interacts with a SafeSingletonFactory contract and a fixed copy of the bytecode of the Safe wallet. 

The team transferred 20 million DVT tokens to a user at `0xCe07CF30B540Bb84ceC5dA5547e1cb4722F9E496`, where her plain 1-of-1 Safe was supposed to land. But they lost the nonce they should use for deployment.

To make matters worse, there's been rumours of a vulnerability in the system. The team's freaked out. Nobody knows what to do, let alone the user. She granted you access to her private key.

You must save all funds before it's too late!

Recover all tokens from the wallet deployer contract and send them to the corresponding ward. Also save and return all user's funds.

In a single transaction.

<!-- ------------------- -->
- If a user deploys a safe wallet, they will 1 DVT as reward. 
- If authorization mechanisism is ON -> Only certain deployers (wards) can be paid for specific wallet deployments -> like a whitelist? 
- Deploys are made by:Deterministic Deployment Proxy -> a contract that deploys contracts with determistic addresses using creates2 -> Safe singleton factory -> Based on DDPs, but specific for Safe contracts AKA wallets (it is already deployed)

- The team transferred 20M DVT to a user `0xCe07CF30B540Bb84ceC5dA5547e1cb4722F9E496` -> this address still not exists, it's supose to be created BUT the user looses the nonce that should be used to deploy a Safe wallet that has such address. 

- I have access to her private key? PK of what? her EOA, but why it is related?

- Recover all tokens and deposit them on the corresponding ward.
