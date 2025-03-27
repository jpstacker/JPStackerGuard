// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

contract JPSMarketplace is 
    ERC721URIStorage, 
    Ownable, 
    ReentrancyGuard, 
    Pausable 
{
    
    // Errors
    error JPSM_SupplyExhausted();
    error JPSM_WalletLimitReached();
    error JPSM_RoyaltyPercentageExceeded();
    error JPSM_InsufficientPayment();
    error JPSM_InvalidParameters();
    error JPSM_Unauthorized();
    error JPSM_AuctionNotActive();
    error JPSM_PriceCalculationError();

    // Core variables
    uint256 private _tokenIds;
    uint256 public totalSupply;
    uint256 public maxPerWallet;
    address public feeRecipient;
    IERC20 public paymentToken; // Optional ERC20 payment support
    
    // Pricing constants
    uint256 public constant PRICE_PRECISION = 1e18;
    uint256 public constant FEE_PRECISION = 10000;
    
    // Dynamic pricing parameters
    struct PricingConfig {
        uint256 basePrice;
        uint256 demandMultiplier;
        uint256 scarcityMultiplier;
        uint256 timeDelayFactor;
        uint256 velocityFactor;        // New: Price adjustment based on sales velocity
        uint256 adjustmentInterval;
        uint256 lastAdjustmentTime;
        uint256 minPrice;             // Minimum price floor
        uint256 maxPrice;             // Maximum price ceiling
    }
    
    PricingConfig public pricingConfig;
    uint256 public marketplaceFee = 250; // 2.5%

    // Advanced token metadata
    enum Rarity { Common, Rare, Epic, Legendary }
    struct TokenData {
        Rarity rarity;
        uint256 royaltyPercentage;
        address royaltyRecipient;
        uint256 mintTime;
        uint256 lastSalePrice;
        uint256 saleCount;
        string category;
    }
    
    // Market structures
    struct Listing {
        uint256 tokenId;
        uint256 price;
        address seller;
        bool active;
        bool acceptsERC20;
        uint256 expiration;
    }
    
    struct Auction {
        uint256 tokenId;
        uint256 currentPrice;
        uint256 reservePrice;
        uint256 duration;
        uint256 startTime;
        uint256 lastBidTime;
        address highestBidder;
        uint256 highestBid;
        bool active;
        bool acceptsERC20;
        uint256 extensionTime; // Auction extension on late bids
    }
    
    struct PriceHistory {
        uint256 timestamp;
        uint256 price;
        uint256 supplyAtTime;
    }

    // Storage
    mapping(uint256 => TokenData) public tokenData;
    mapping(Rarity => uint256) public rarityMultipliers;
    mapping(address => uint256) public walletPurchases;
    mapping(uint256 => Listing) public listings;
    mapping(uint256 => Auction) public auctions;
    mapping(uint256 => PriceHistory[]) public priceHistory;
    mapping(address => uint256) public pendingWithdrawals;
    mapping(uint256 => uint256) public recentSalesVelocity; // Sales in last interval

    // Events
    event NFTMinted(uint256 indexed tokenId, address recipient, uint256 price, Rarity rarity);
    event PriceAdjusted(uint256 newBasePrice, uint256 timestamp);
    event Listed(uint256 indexed tokenId, uint256 price, address seller);
    event Purchased(uint256 indexed tokenId, address buyer, uint256 price);
    event AuctionStarted(uint256 indexed tokenId, uint256 startingPrice, uint256 duration);
    event BidPlaced(uint256 indexed tokenId, address bidder, uint256 amount);
    event AuctionExtended(uint256 indexed tokenId, uint256 newEndTime);
    event AuctionEnded(uint256 indexed tokenId, address winner, uint256 amount);

    constructor(
        uint256 _basePrice,
        uint256 _totalSupply,
        uint256 _maxPerWallet,
        address _feeRecipient,
        address _paymentToken // Optional ERC20 token address
    ) ERC721("JP Stacker Marketplace", "JPS") Ownable(msg.sender) {
        totalSupply = _totalSupply;
        maxPerWallet = _maxPerWallet;
        feeRecipient = _feeRecipient;
        paymentToken = IERC20(_paymentToken);

        pricingConfig = PricingConfig({
            basePrice: _basePrice,
            demandMultiplier: 150,      // 1.5x
            scarcityMultiplier: 200,    // 2x
            timeDelayFactor: 50,        // 0.5x
            velocityFactor: 100,        // 1x
            adjustmentInterval: 1 days,
            lastAdjustmentTime: block.timestamp,
            minPrice: _basePrice / 10,  // 10% of base
            maxPrice: _basePrice * 10   // 10x base
        });

        rarityMultipliers[Rarity.Common] = 100;
        rarityMultipliers[Rarity.Rare] = 150;
        rarityMultipliers[Rarity.Epic] = 300;
        rarityMultipliers[Rarity.Legendary] = 500;
    }

    // --- Advanced Dynamic Pricing ---

    function getCurrentPrice(Rarity _rarity) public view returns (uint256) {
        uint256 currentSupply = _tokenIds;
        if (currentSupply >= totalSupply) return pricingConfig.basePrice;

        // Demand factor based on current supply
        uint256 demandFactor = (currentSupply * pricingConfig.demandMultiplier * PRICE_PRECISION) / totalSupply;

        // Scarcity factor with protection against division by zero
        uint256 leftoverSupply = totalSupply - currentSupply;
        uint256 scarcityFactor = leftoverSupply > 0 
            ? (totalSupply * pricingConfig.scarcityMultiplier * PRICE_PRECISION) / leftoverSupply 
            : PRICE_PRECISION;

        // Time decay with velocity adjustment
        uint256 timeSinceLast = block.timestamp - pricingConfig.lastAdjustmentTime;
        uint256 decay = (timeSinceLast * pricingConfig.timeDelayFactor * pricingConfig.basePrice) / 
            (PRICE_PRECISION * 24 hours);
        uint256 velocityAdjustment = (recentSalesVelocity[block.timestamp / pricingConfig.adjustmentInterval] * 
            pricingConfig.velocityFactor * PRICE_PRECISION) / 100;
        
        uint256 timeAdjustedPrice = pricingConfig.basePrice > decay 
            ? pricingConfig.basePrice - decay + velocityAdjustment 
            : pricingConfig.basePrice + velocityAdjustment;

        // Combine factors with bounds checking
        uint256 dynamicPrice = timeAdjustedPrice * 
            (PRICE_PRECISION + demandFactor + scarcityFactor) / 
            PRICE_PRECISION;

        dynamicPrice = (dynamicPrice * rarityMultipliers[_rarity]) / 100;
        
        // Apply price bounds
        if (dynamicPrice < pricingConfig.minPrice) return pricingConfig.minPrice;
        if (dynamicPrice > pricingConfig.maxPrice) return pricingConfig.maxPrice;
        
        return dynamicPrice;
    }

    function updatePricingConfig(
        uint256 _demandMultiplier,
        uint256 _scarcityMultiplier,
        uint256 _timeDelayFactor,
        uint256 _velocityFactor
    ) external onlyOwner {
        pricingConfig.demandMultiplier = _demandMultiplier;
        pricingConfig.scarcityMultiplier = _scarcityMultiplier;
        pricingConfig.timeDelayFactor = _timeDelayFactor;
        pricingConfig.velocityFactor = _velocityFactor;
        pricingConfig.lastAdjustmentTime = block.timestamp;
        emit PriceAdjusted(pricingConfig.basePrice, block.timestamp);
    }

    // --- Minting ---

    function mintNFT(
        string memory _tokenURI,
        string memory _category,
        Rarity _rarity,
        uint256 _royaltyPercentage
    ) 
        external 
        payable 
        whenNotPaused 
        nonReentrant 
        returns (uint256) 
    {
        if (_tokenIds >= totalSupply) revert JPSM_SupplyExhausted();
        if (walletPurchases[msg.sender] >= maxPerWallet) revert JPSM_WalletLimitReached();
        if (_royaltyPercentage > 2500) revert JPSM_RoyaltyPercentageExceeded();

        uint256 price = getCurrentPrice(_rarity);
        if (msg.value <= price) revert JPSM_InsufficientPayment();

        _tokenIds++;
        
        _safeMint(msg.sender, _tokenIds);
        _setTokenURI(_tokenIds, _tokenURI);
        
        tokenData[_tokenIds] = TokenData({
            rarity: _rarity,
            royaltyPercentage: _royaltyPercentage,
            royaltyRecipient: msg.sender,
            mintTime: block.timestamp,
            lastSalePrice: price,
            saleCount: 1,
            category: _category
        });
        
        walletPurchases[msg.sender]++;
        pricingConfig.lastAdjustmentTime = block.timestamp;
        recentSalesVelocity[block.timestamp / pricingConfig.adjustmentInterval]++;
        
        priceHistory[_tokenIds].push(PriceHistory(block.timestamp, price, _tokenIds));
        
        if (msg.value > price) {
            _safeTransferETH(msg.sender, msg.value - price);
        }

        emit NFTMinted(_tokenIds, msg.sender, price, _rarity);
        return _tokenIds;
    }

    // --- Marketplace ---

    function listNFT(
        uint256 _tokenId,
        uint256 _price,
        bool _acceptsERC20,
        uint256 _duration
    ) 
        external 
        whenNotPaused 
    {
        if (ownerOf(_tokenId) != msg.sender) revert JPSM_Unauthorized();
        if (_price == 0 || _duration == 0) revert JPSM_InvalidParameters();
        if (listings[_tokenId].active || auctions[_tokenId].active) revert JPSM_InvalidParameters();

        _transfer(msg.sender, address(this), _tokenId);
        listings[_tokenId] = Listing({
            tokenId: _tokenId,
            price: _price,
            seller: msg.sender,
            active: true,
            acceptsERC20: _acceptsERC20,
            expiration: block.timestamp + _duration
        });

        emit Listed(_tokenId, _price, msg.sender);
    }

    function buyNFT(
        uint256 _tokenId, 
        bool _useERC20
    ) 
        external 
        payable 
        whenNotPaused 
        nonReentrant 
    {
        Listing memory listing = listings[_tokenId];
        if (!listing.active || block.timestamp > listing.expiration) revert JPSM_InvalidParameters();

        uint256 price = listing.price;
        _processPayment(listing, price, _useERC20);
        
        _processSale(_tokenId, msg.sender, price, listing.seller);
        emit Purchased(_tokenId, msg.sender, price);
    }

    // --- Auctions ---

    function startAuction(
        uint256 _tokenId,
        uint256 _reservePrice,
        uint256 _duration,
        bool _acceptsERC20,
        uint256 _extensionTime
    ) 
        external 
        whenNotPaused 
    {
        if (ownerOf(_tokenId) != msg.sender) revert JPSM_Unauthorized();
        if (_duration == 0 || _reservePrice == 0) revert JPSM_InvalidParameters();
        if (auctions[_tokenId].active || listings[_tokenId].active) revert JPSM_InvalidParameters();

        uint256 startPrice = getCurrentPrice(tokenData[_tokenId].rarity);
        _transfer(msg.sender, address(this), _tokenId);
        
        auctions[_tokenId] = Auction({
            tokenId: _tokenId,
            currentPrice: startPrice,
            reservePrice: _reservePrice,
            duration: _duration,
            startTime: block.timestamp,
            lastBidTime: 0,
            highestBidder: address(0),
            highestBid: 0,
            active: true,
            acceptsERC20: _acceptsERC20,
            extensionTime: _extensionTime
        });

        emit AuctionStarted(_tokenId, startPrice, _duration);
    }

    function placeBid(
        uint256 _tokenId, 
        bool _useERC20
    ) 
        external 
        payable 
        whenNotPaused 
        nonReentrant 
    {
        Auction storage auction = auctions[_tokenId];
        if (!auction.active) revert JPSM_AuctionNotActive();
        
        uint256 endTime = auction.startTime + auction.duration;
        if (block.timestamp >= endTime) revert JPSM_AuctionNotActive();

        uint256 minBid = auction.highestBid == 0 
            ? auction.currentPrice 
            : auction.highestBid + (auction.highestBid * 5) / 100; // 5% minimum increment
            
        _processPaymentForBid(auction, minBid, _useERC20);

        // Refund previous bidder
        if (auction.highestBidder != address(0)) {
            pendingWithdrawals[auction.highestBidder] += auction.highestBid;
        }

        // Extend auction if bid is in last 5 minutes
        if (endTime - block.timestamp < 5 minutes && auction.extensionTime > 0) {
            auction.duration += auction.extensionTime;
            emit AuctionExtended(_tokenId, endTime + auction.extensionTime);
        }

        auction.highestBidder = msg.sender;
        auction.highestBid = _useERC20 ? minBid : msg.value;
        auction.lastBidTime = block.timestamp;

        emit BidPlaced(_tokenId, msg.sender, auction.highestBid);
    }

    function endAuction(uint256 _tokenId) external nonReentrant {
        Auction storage auction = auctions[_tokenId];
        if (!auction.active) revert JPSM_AuctionNotActive();
        if (block.timestamp < auction.startTime + auction.duration && 
            msg.sender != owner() && 
            msg.sender != ownerOf(_tokenId)) 
            revert JPSM_AuctionNotActive();

        auction.active = false;
        if (auction.highestBid >= auction.reservePrice && auction.highestBidder != address(0)) {
            _processSale(_tokenId, auction.highestBidder, auction.highestBid, ownerOf(_tokenId));
            emit AuctionEnded(_tokenId, auction.highestBidder, auction.highestBid);
        } else {
            _transfer(address(this), ownerOf(_tokenId), _tokenId);
            emit AuctionEnded(_tokenId, address(0), 0);
        }
    }

    // --- Internal Functions ---

    function _processPayment(Listing memory _listing, uint256 _amount, bool _useERC20) internal {
        if (_useERC20) {
            if (!_listing.acceptsERC20) revert JPSM_InvalidParameters();
            if (paymentToken.transferFrom(msg.sender, address(this), _amount)) 
                revert JPSM_InsufficientPayment();
        } else {
            if (msg.value < _amount) revert JPSM_InsufficientPayment();
        }
    }

    function _processPaymentForBid(
        Auction memory _auction, 
        uint256 _amount, 
        bool _useERC20
    ) 
        internal 
    {
        if (_useERC20) {
            if (!_auction.acceptsERC20) revert JPSM_InvalidParameters();
            if (!paymentToken.transferFrom(msg.sender, address(this), _amount)) 
                revert JPSM_InsufficientPayment();
        } else {
            if (msg.value < _amount) revert JPSM_InsufficientPayment();
        }
    }

    function _processSale(
        uint256 _tokenId, 
        address _buyer, 
        uint256 _amount, 
        address _seller
    ) 
        internal 
    {
        TokenData storage data = tokenData[_tokenId];
        listings[_tokenId].active = false;

        uint256 royaltyAmount = (_amount * data.royaltyPercentage) / FEE_PRECISION;
        uint256 feeAmount = (_amount * marketplaceFee) / FEE_PRECISION;
        uint256 sellerAmount = _amount - royaltyAmount - feeAmount;

        _safeTransferETH(data.royaltyRecipient, royaltyAmount);
        _safeTransferETH(feeRecipient, feeAmount);
        _safeTransferETH(_seller, sellerAmount);
        
        _transfer(address(this), _buyer, _tokenId);
        
        data.lastSalePrice = _amount;
        data.saleCount++;
        priceHistory[_tokenId].push(PriceHistory(block.timestamp, _amount, _tokenIds));
        recentSalesVelocity[block.timestamp / pricingConfig.adjustmentInterval]++;
        
        if (msg.value > _amount) {
            _safeTransferETH(msg.sender, msg.value - _amount);
        }
    }

    function _safeTransferETH(address _to, uint256 _amount) internal {
        (bool success, ) = _to.call{value: _amount}("");
        require(success, "ETH transfer failed");
    }

    // --- Admin Functions ---

    function updateFee(uint256 _newFee) external onlyOwner {
        if (_newFee > 1000) revert JPSM_InvalidParameters(); // Max 10%
        marketplaceFee = _newFee;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // --- View Functions ---

    function getTokenDetails(uint256 _tokenId) external view returns (TokenData memory) {
        return tokenData[_tokenId];
    }

    function getPriceHistory(uint256 _tokenId) external view returns (PriceHistory[] memory) {
        return priceHistory[_tokenId];
    }

    function remainingSupply() external view returns (uint256) {
        return totalSupply - _tokenIds;
    }
}