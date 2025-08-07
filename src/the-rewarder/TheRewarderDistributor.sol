// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {BitMaps} from "@openzeppelin/contracts/utils/structs/BitMaps.sol";

// @i each token has one of this. Holds distribution data and roots of each batch and claims of users
struct Distribution {
    uint256 remaining;
    uint256 nextBatchNumber;
    mapping(uint256 batchNumber => bytes32 root) roots;
    // @q How does the bitmap work?
    mapping(address claimer => mapping(uint256 word => uint256 bits)) claims;
}

struct Claim {
    uint256 batchNumber;
    uint256 amount;
    uint256 tokenIndex; // @q index on the token list?
    bytes32[] proof;
}

/**
 * An efficient token distributor contract based on Merkle proofs and bitmaps
 */
contract TheRewarderDistributor {
    using BitMaps for BitMaps.BitMap;

    address public immutable owner = msg.sender;

    mapping(IERC20 token => Distribution) public distributions;

    error StillDistributing();
    error InvalidRoot();
    error AlreadyClaimed();
    error InvalidProof();
    error NotEnoughTokensToDistribute();

    event NewDistribution(IERC20 token, uint256 batchNumber, bytes32 newMerkleRoot, uint256 totalAmount);

    function getRemaining(address token) external view returns (uint256) {
        return distributions[IERC20(token)].remaining;
    }

    function getNextBatchNumber(address token) external view returns (uint256) {
        return distributions[IERC20(token)].nextBatchNumber;
    }

    function getRoot(address token, uint256 batchNumber) external view returns (bytes32) {
        return distributions[IERC20(token)].roots[batchNumber];
    }

    function createDistribution(IERC20 token, bytes32 newRoot, uint256 amount) external {
        if (amount == 0) revert NotEnoughTokensToDistribute();
        if (newRoot == bytes32(0)) revert InvalidRoot();
        if (distributions[token].remaining != 0) revert StillDistributing();

        distributions[token].remaining = amount;

        uint256 batchNumber = distributions[token].nextBatchNumber;
        distributions[token].roots[batchNumber] = newRoot;
        distributions[token].nextBatchNumber++;

        // @notice this contract holds the tokens
        SafeTransferLib.safeTransferFrom(address(token), msg.sender, address(this), amount);

        emit NewDistribution(token, batchNumber, newRoot, amount);
    }

    function clean(IERC20[] calldata tokens) external {
        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20 token = tokens[i];
            if (distributions[token].remaining == 0) { // @audit like for transfer direct transfers and so on? cause only exec if remaining is 0
                token.transfer(owner, token.balanceOf(address(this)));
            }
        }
    }

    // Allow claiming rewards of multiple tokens in a single transaction
    function claimRewards(Claim[] memory inputClaims, IERC20[] memory inputTokens) external {
        Claim memory inputClaim;
        IERC20 token;
        uint256 bitsSet; // accumulator
        uint256 amount;

        for (uint256 i = 0; i < inputClaims.length; i++) {
            // take claim 
            inputClaim = inputClaims[i];

            uint256 wordPosition = inputClaim.batchNumber / 256; // 0=0, 1=0, 2=0... 256=1...512=2...
            uint256 bitPosition = inputClaim.batchNumber % 256; // 0 to 256 and repeat infinitely 

            // if token is diff to the calim token
            if (token != inputTokens[inputClaim.tokenIndex]) {
                // @notice when token changes after setting the first one
                // first iteration -> true & false -> false
                // second iteration
                //          -> if same token: false & false -> false
                //          -> no same token: true & true -> true
                if (address(token) != address(0)) {
                    if (!_setClaimed(token, amount, wordPosition, bitsSet)) revert AlreadyClaimed();
                }

                token = inputTokens[inputClaim.tokenIndex];

                bitsSet = 1 << bitPosition; // set bit at given position -> first batch 0001, second 0010, third 0100...
                amount = inputClaim.amount;
            } else { // if token is repeated
            // 0001 | 0001 = 0001
                bitsSet = bitsSet | 1 << bitPosition; // first batch 0001, second 0001 | 0010 = 0011, third 0011 | 0100 = 0111...
                amount += inputClaim.amount;
            }

            // for the last claim  AKA evaluates latest loop when detects a token change
            // @audit@notice if token changes btw claims, _setClaimed is called on each change
            // if you send the same token, setClaimed is called only at the end of the loop
            // Also, 1st iteration dont call this cause token is 0, then conditional falls to else
            // and in else, bitset never changes (cause is the same claim) so it just transfer without checking if already claimed and without register the claim in state
            // It's like a kind of reentrancy, cause is transfering the tokens, then on next loop 'reenters' before state is updated
            if (i == inputClaims.length - 1) {
                if (!_setClaimed(token, amount, wordPosition, bitsSet)) revert AlreadyClaimed();
            }

            // merkle leaf = receiver + amount
            bytes32 leaf = keccak256(abi.encodePacked(msg.sender, inputClaim.amount));
            bytes32 root = distributions[token].roots[inputClaim.batchNumber];

            if (!MerkleProof.verify(inputClaim.proof, root, leaf)) revert InvalidProof();
            
            // @audit transfer amount each loop 
            inputTokens[inputClaim.tokenIndex].transfer(msg.sender, inputClaim.amount);
        }
    }

    // @audit this always has to throw true or claimRewards will revert 
    // If I repeat the same claim on the claims array, this still throws true, even if cliam was already claimed 
    // why?
    // let's loop on it
    /*
    
    claims[0] = Claim({
        batchNumber: 0, 
        amount: claimAmountDVT,
        tokenIndex: 0, 
        proof: merkle.getProof(dvtLeaves, leaveIndexDVT)
    });

    params on each loop:
    first loop:  wordPosition=0 newBits=0001
    second loop: wordPosition=0 newBits=0001
    third loop:  wordPosition=0 newBits=0001

     */ 
    // @notice wordPosition = will be always 0 during the first 256 batches (so use a single u256 to record the first batches, then move to the next key on the mapping once this one is fulled)
    function _setClaimed(IERC20 token, uint256 amount, uint256 wordPosition, uint256 newBits) private returns (bool) {
        // distributions->token->claimer->word position->bits aka word
        uint256 currentWord = distributions[token].claims[msg.sender][wordPosition];
        // 0000 & 0001 => 0000 AKA has not claim
        // 0001 & 0001 => 
        if ((currentWord & newBits) != 0) return false; // has already claimed, so revert

        // update state
        // 0000 | 0001 = 0001
        distributions[token].claims[msg.sender][wordPosition] = currentWord | newBits;
        distributions[token].remaining -= amount;

        return true;
    }
}
