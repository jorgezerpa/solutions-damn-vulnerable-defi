// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {DamnValuableToken} from "../DamnValuableToken.sol";

contract PuppetPool is ReentrancyGuard {
    using Address for address payable;

    uint256 public constant DEPOSIT_FACTOR = 2;

    address public immutable uniswapPair;
    DamnValuableToken public immutable token;

    mapping(address => uint256) public deposits;

    error NotEnoughCollateral();
    error TransferFailed();

    event Borrowed(address indexed account, address recipient, uint256 depositRequired, uint256 borrowAmount);

    constructor(address tokenAddress, address uniswapPairAddress) {
        token = DamnValuableToken(tokenAddress);
        uniswapPair = uniswapPairAddress;
    }

    // Allows borrowing tokens by first depositing two times their value in ETH
    function borrow(uint256 amount, address recipient) external payable nonReentrant {
        uint256 depositRequired = calculateDepositRequired(amount);

        if (msg.value < depositRequired) {
            revert NotEnoughCollateral();
        }

        // give back excess
        if (msg.value > depositRequired) {
            unchecked {
                payable(msg.sender).sendValue(msg.value - depositRequired);
            }
        }

        unchecked {
            deposits[msg.sender] += depositRequired;
        }

        // Fails if the pool doesn't have enough tokens in liquidity
        // @audit I need to take out the exact amount of tokens holded by the pool 
        if (!token.transfer(recipient, amount)) {
            revert TransferFailed();
        }

        emit Borrowed(msg.sender, recipient, depositRequired, amount);
    }

    function calculateDepositRequired(uint256 amount) public view returns (uint256) {
        // receives the amount of tokens I want to get
        // amount * priceOfEth
        // 1:1 -> 10 * (1 * 2) -> 2 
        // 2:1 -> 10 * (2 * 2) -> 4
        // 1:2 -> 10 * (0.5 * 2) -> 1
        // 0.1:2 -> 10 * (0.2 * 2) -> 0.4
        return amount * _computeOraclePrice() * DEPOSIT_FACTOR / 10 ** 18; // fixed point a*b = a*b/denominator
    }

    // @notice return eth/token
    // 1 eth/token -> 1 token word 1 eth
    // 5 eth/token -> 1 token word 5 eth
    function _computeOraclePrice() private view returns (uint256) {
        // calculates the price of the token in wei according to Uniswap pair
        // 1:1 -> 1
        // 2:1 -> 2
        // 1:2 -> 0.5
        return uniswapPair.balance * (10 ** 18) / token.balanceOf(uniswapPair);
    }
}
