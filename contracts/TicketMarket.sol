// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "./IRuleEngine.sol";
import "./TicketCollection.sol";

/// @title TicketMarket
/// @notice 去中心化票務市集合約，支援票券上架、購買和費率計算
/// @dev 整合 RuleEngineV1 進行價格限制和動態費率計算
contract TicketMarket is ReentrancyGuard, Ownable, ERC1155Holder {
    
    /// @dev 上架信息結構
    struct Listing {
        address seller;           // 賣家地址
        address collection;       // 票券合約地址
        uint256 tokenId;         // 代幣 ID
        uint256 amount;          // 上架數量
        uint256 pricePerTicket;  // 每張票價格（wei）
        uint256 listingTime;     // 上架時間
        bool active;             // 是否有效
    }

    /// @notice 平台費率（基點，10000 = 100%）
    uint256 public platformFeeBps = 250; // 2.5%
    
    /// @notice 平台費用接收地址
    address public feeRecipient;
    
    /// @notice 上架計數器
    uint256 public listingCounter;
    
    /// @notice 上架信息映射
    mapping(bytes32 => Listing) public listings;
    
    /// @notice 用戶的活躍上架列表
    mapping(address => bytes32[]) public userListings;
    
    /// @notice 合約的活躍上架列表
    mapping(address => bytes32[]) public collectionListings;

    /// @dev 事件定義
    event TicketListed(
        bytes32 indexed listingId,
        address indexed seller,
        address indexed collection,
        uint256 tokenId,
        uint256 amount,
        uint256 pricePerTicket
    );
    
    event TicketSold(
        bytes32 indexed listingId,
        address indexed buyer,
        address indexed seller,
        address collection,
        uint256 tokenId,
        uint256 amount,
        uint256 totalPrice,
        uint256 platformFee,
        uint256 ruleFee
    );
    
    event ListingCancelled(
        bytes32 indexed listingId,
        address indexed seller
    );
    
    event PlatformFeeUpdated(uint256 oldFeeBps, uint256 newFeeBps);
    event FeeRecipientUpdated(address indexed oldRecipient, address indexed newRecipient);

    /// @param _feeRecipient 平台費用接收地址
    constructor(address _feeRecipient) Ownable(msg.sender) {
        require(_feeRecipient != address(0), "TicketMarket: invalid fee recipient");
        feeRecipient = _feeRecipient;
    }

    /// @notice 上架票券
    /// @param collection 票券合約地址
    /// @param tokenId 代幣 ID
    /// @param amount 上架數量
    /// @param pricePerTicket 每張票價格（wei）
    /// @return listingId 上架 ID
    function listTicket(
        address collection,
        uint256 tokenId,
        uint256 amount,
        uint256 pricePerTicket
    ) external nonReentrant returns (bytes32 listingId) {
        require(collection != address(0), "TicketMarket: invalid collection");
        require(amount > 0, "TicketMarket: invalid amount");
        require(pricePerTicket > 0, "TicketMarket: invalid price");
        
        // 檢查賣家是否持有足夠的票券
        IERC1155 ticketContract = IERC1155(collection);
        require(
            ticketContract.balanceOf(msg.sender, tokenId) >= amount,
            "TicketMarket: insufficient balance"
        );
        
        // 檢查是否已授權市集合約
        require(
            ticketContract.isApprovedForAll(msg.sender, address(this)),
            "TicketMarket: not approved"
        );

        // 如果是 TicketCollection，檢查價格是否符合規則引擎限制
        if (_isTicketCollection(collection)) {
            _validatePriceWithRuleEngine(collection, tokenId, amount, pricePerTicket);
        }

        // 生成上架 ID
        listingId = keccak256(abi.encodePacked(
            msg.sender,
            collection,
            tokenId,
            amount,
            pricePerTicket,
            block.timestamp,
            listingCounter++
        ));

        // 創建上架信息
        listings[listingId] = Listing({
            seller: msg.sender,
            collection: collection,
            tokenId: tokenId,
            amount: amount,
            pricePerTicket: pricePerTicket,
            listingTime: block.timestamp,
            active: true
        });

        // 更新索引
        userListings[msg.sender].push(listingId);
        collectionListings[collection].push(listingId);

        emit TicketListed(listingId, msg.sender, collection, tokenId, amount, pricePerTicket);
        
        return listingId;
    }

    /// @notice 購買票券
    /// @param listingId 上架 ID
    /// @param amount 購買數量
    function buyTicket(bytes32 listingId, uint256 amount) 
        external 
        payable 
        nonReentrant 
    {
        Listing storage listing = listings[listingId];
        require(listing.active, "TicketMarket: listing not active");
        require(listing.seller != msg.sender, "TicketMarket: cannot buy own ticket");
        require(amount > 0 && amount <= listing.amount, "TicketMarket: invalid amount");

        uint256 totalPrice = listing.pricePerTicket * amount;
        require(msg.value >= totalPrice, "TicketMarket: insufficient payment");

        // 計算費用
        uint256 platformFee = (totalPrice * platformFeeBps) / 10000;
        uint256 ruleFee = 0;
        
        // 如果是 TicketCollection，計算規則引擎費用
        if (_isTicketCollection(listing.collection)) {
            ruleFee = _calculateRuleFee(listing.collection, listing.tokenId, amount, totalPrice);
        }

        uint256 sellerAmount = totalPrice - platformFee - ruleFee;

        // 執行轉帳
        if (_isTicketCollection(listing.collection)) {
            // 使用帶價格的轉帳函數
            TicketCollection(listing.collection).safeTransferFromWithPrice(
                listing.seller,
                msg.sender,
                listing.tokenId,
                amount,
                totalPrice,
                "", // zkRegionProof
                "", // zkAgeProof
                ""  // data
            );
        } else {
            // 普通 ERC1155 轉帳
            IERC1155(listing.collection).safeTransferFrom(
                listing.seller,
                msg.sender,
                listing.tokenId,
                amount,
                ""
            );
        }

        // 分配資金
        if (platformFee > 0) {
            payable(feeRecipient).transfer(platformFee);
        }
        
        if (ruleFee > 0) {
            // 規則引擎費用發送給合約 owner
            TicketCollection ticketCollection = TicketCollection(listing.collection);
            payable(ticketCollection.owner()).transfer(ruleFee);
        }
        
        payable(listing.seller).transfer(sellerAmount);

        // 更新上架信息
        listing.amount -= amount;
        if (listing.amount == 0) {
            listing.active = false;
        }

        // 退還多餘的 ETH
        if (msg.value > totalPrice) {
            payable(msg.sender).transfer(msg.value - totalPrice);
        }

        emit TicketSold(
            listingId,
            msg.sender,
            listing.seller,
            listing.collection,
            listing.tokenId,
            amount,
            totalPrice,
            platformFee,
            ruleFee
        );
    }

    /// @notice 取消上架
    /// @param listingId 上架 ID
    function cancelListing(bytes32 listingId) external nonReentrant {
        Listing storage listing = listings[listingId];
        require(listing.active, "TicketMarket: listing not active");
        require(listing.seller == msg.sender, "TicketMarket: not seller");

        listing.active = false;

        emit ListingCancelled(listingId, msg.sender);
    }

    /// @notice 計算購買費用（不包含平台費）
    /// @param collection 票券合約地址
    /// @param tokenId 代幣 ID
    /// @param amount 購買數量
    /// @param pricePerTicket 每張票價格
    /// @return totalPrice 總價格
    /// @return platformFee 平台費
    /// @return ruleFee 規則引擎費用
    function calculateFees(
        address collection,
        uint256 tokenId,
        uint256 amount,
        uint256 pricePerTicket
    ) external view returns (uint256 totalPrice, uint256 platformFee, uint256 ruleFee) {
        totalPrice = pricePerTicket * amount;
        platformFee = (totalPrice * platformFeeBps) / 10000;
        
        if (_isTicketCollection(collection)) {
            ruleFee = _calculateRuleFee(collection, tokenId, amount, totalPrice);
        }
    }

    /// @notice 獲取最高可售價
    /// @param collection 票券合約地址
    /// @param tokenId 代幣 ID
    /// @return maxPrice 最高可售價（每張票）
    function getMaxAllowedPrice(address collection, uint256 tokenId) 
        external 
        view 
        returns (uint256 maxPrice) 
    {
        if (!_isTicketCollection(collection)) {
            return type(uint256).max; // 非 TicketCollection 沒有價格限制
        }

        TicketCollection ticketCollection = TicketCollection(collection);
        IRuleEngine ruleEngine = ticketCollection.ruleEngine();
        
        if (address(ruleEngine) == address(0)) {
            return type(uint256).max;
        }

        // 這裡需要訪問 RuleEngineV1 的參數，但由於接口限制，
        // 實際實現中可能需要添加額外的 getter 函數
        // 暫時返回一個大數值，實際使用時需要優化
        return type(uint256).max;
    }

    /// @notice 獲取用戶的活躍上架列表
    /// @param user 用戶地址
    /// @return activeListings 活躍上架 ID 列表
    function getUserActiveListings(address user) 
        external 
        view 
        returns (bytes32[] memory activeListings) 
    {
        bytes32[] memory userListingIds = userListings[user];
        uint256 activeCount = 0;
        
        // 計算活躍上架數量
        for (uint256 i = 0; i < userListingIds.length; i++) {
            if (listings[userListingIds[i]].active) {
                activeCount++;
            }
        }
        
        // 構建活躍上架列表
        activeListings = new bytes32[](activeCount);
        uint256 index = 0;
        for (uint256 i = 0; i < userListingIds.length; i++) {
            if (listings[userListingIds[i]].active) {
                activeListings[index] = userListingIds[i];
                index++;
            }
        }
    }

    /// @notice 設定平台費率（僅 owner）
    /// @param newFeeBps 新的費率（基點）
    function setPlatformFee(uint256 newFeeBps) external onlyOwner {
        require(newFeeBps <= 1000, "TicketMarket: fee too high"); // 最高 10%
        uint256 oldFeeBps = platformFeeBps;
        platformFeeBps = newFeeBps;
        emit PlatformFeeUpdated(oldFeeBps, newFeeBps);
    }

    /// @notice 設定費用接收地址（僅 owner）
    /// @param newRecipient 新的接收地址
    function setFeeRecipient(address newRecipient) external onlyOwner {
        require(newRecipient != address(0), "TicketMarket: invalid recipient");
        address oldRecipient = feeRecipient;
        feeRecipient = newRecipient;
        emit FeeRecipientUpdated(oldRecipient, newRecipient);
    }

    /// @dev 檢查是否為 TicketCollection 合約
    function _isTicketCollection(address collection) private view returns (bool) {
        try TicketCollection(collection).ruleEngine() returns (IRuleEngine) {
            return true;
        } catch {
            return false;
        }
    }

    /// @dev 使用規則引擎驗證價格
    function _validatePriceWithRuleEngine(
        address collection,
        uint256 tokenId,
        uint256 amount,
        uint256 pricePerTicket
    ) private view {
        TicketCollection ticketCollection = TicketCollection(collection);
        IRuleEngine ruleEngine = ticketCollection.ruleEngine();
        
        if (address(ruleEngine) == address(0)) {
            return; // 沒有規則引擎，跳過檢查
        }

        IRuleEngine.TransferCtx memory ctx = IRuleEngine.TransferCtx({
            from: msg.sender,
            to: address(0), // 在上架時 to 地址未知
            tokenId: tokenId,
            amount: amount,
            priceWei: pricePerTicket * amount,
            time: block.timestamp,
            zkRegionProof: "",
            zkAgeProof: ""
        });

        (bool allowed, , string memory reason) = ruleEngine.check(ctx);
        require(allowed, string(abi.encodePacked("TicketMarket: ", reason)));
    }

    /// @dev 計算規則引擎費用
    function _calculateRuleFee(
        address collection,
        uint256 tokenId,
        uint256 amount,
        uint256 totalPrice
    ) private view returns (uint256) {
        TicketCollection ticketCollection = TicketCollection(collection);
        IRuleEngine ruleEngine = ticketCollection.ruleEngine();
        
        if (address(ruleEngine) == address(0)) {
            return 0;
        }

        IRuleEngine.TransferCtx memory ctx = IRuleEngine.TransferCtx({
            from: address(0), // 在計算費用時 from 地址可能未知
            to: address(0),   // 在計算費用時 to 地址可能未知
            tokenId: tokenId,
            amount: amount,
            priceWei: totalPrice,
            time: block.timestamp,
            zkRegionProof: "",
            zkAgeProof: ""
        });

        (, uint96 feeBps, ) = ruleEngine.check(ctx);
        return (totalPrice * uint256(feeBps)) / 10000;
    }
}
