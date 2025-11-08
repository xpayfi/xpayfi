// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./Ownable.sol";
import "./Math.sol";
import "./ReentrancyGuard.sol";

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(
        address recipient,
        uint256 amount
    ) external returns (bool);
    function allowance(
        address owner,
        address spender
    ) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);
    function mint(address to, uint256 amount) external;
}

interface IUniswapV2Router {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
    function getAmountsOut(
        uint256 amountIn,
        address[] calldata path
    ) external view returns (uint256[] memory amounts);
    function getAmountsIn(
        uint256 amountOut,
        address[] calldata path
    ) external view returns (uint256[] memory amounts);
}

interface IUniswapV2Pair {
    function getReserves()
        external
        view
        returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function token0() external view returns (address);
    function token1() external view returns (address);
}

/**
 * XPayFi DeFi Protocol
 * Integrate all core functions such as minting, pledging, node buying, and Flux buying
 */
contract XPayFiProtocol is Ownable, ReentrancyGuard {
    using Math for uint256;

    // ============== Core Configuration ==============
    IERC20 public immutable usdt;
    IERC20 public xfi;
    IUniswapV2Router public immutable router;
    IUniswapV2Pair public immutable xfiUsdtPair;

    address public treasuryAddress;
    address public marketAddress;
    address public burnAddress;
    address public mintReceiveAddress;

    // ============== Universal Constant ==============
    uint256 public constant SECONDS_PER_DAY = 86400;
    uint256 public constant MULTIPLIER_BASE = 1000;
    uint256 public constant MIN_MINT_AMOUNT = 10 * 1e18;
    // FLUX Cooling-off period 48
    uint256 public constant FLUX_HOLDING_PERIOD = 48 hours;
    uint256 public constant PERCENT_BASE = 100;
    uint256 public constant INVITER_BONUS_RATE = 10;

    // ============== Generic data structure ==============


    struct FluxOrder {
        address user;
        uint256 xfiAmount;
        uint256 usdtPaid;
        uint256 createTime;
        uint256 unlockTime;
        bool isActive;
        bool isClaimed;
        string source; // Source module (mint, stake, node)
    }

    struct MintOrder {
        uint256 usdtAmount;
        uint256 xfiAmount;
        uint256 rewardPerSecond;
        uint256 startTime;
        uint256 endTime;
        uint256 lastClaimTime;
        uint256 totalClaimed;
        uint8 period;
        bool isActive;
    }

    struct PeriodConfig {
        uint256 daysTime;
        uint256 multiplier;
    }

    struct StakeOrder {
        uint256 xfiAmount;
        uint256 rewardPerSecond;
        uint256 startTime;
        uint256 endTime;
        uint256 lastClaimTime;
        uint256 totalClaimed;
        uint8 period;
        uint256 dailyRate;
        bool isActive;
        bool canWithdraw;
    }

    // ============== State Mapping ==============

    // Invitation Relationship (Globally Unified)
    mapping(address => address) public inviterMap;

    // Whether there is an order
    mapping(address => bool) public hasValidOrder;

    // Flux Orders (Globally Unified)
    mapping(address => FluxOrder[]) public userFluxOrders;

    // Coin Module
    mapping(address => MintOrder[]) public userMintOrders;
    mapping(uint256 => PeriodConfig) public mintPeriodConfigs;

    // Pledge module
    mapping(address => StakeOrder[]) public userStakeOrders;
    mapping(uint256 => uint256) public stakeDailyRates;

    // ============== Event Definition ==============

    event FluxOrderCreated(
        address indexed user,
        uint256 orderIndex,
        uint256 xfiAmount,
        uint256 usdtRequired,
        string source
    );

    event FluxOrderPaid(
        address indexed user,
        uint256 orderIndex,
        uint256 usdtPaid
    );

    event FluxRewardClaimed(
        address indexed user,
        uint256 orderIndex,
        uint256 xfiAmount
    );

    // 铸币模块事件
    event MintEvent(
        address indexed user,
        uint256 usdtAmount,
        uint256 xfiAmount,
        uint8 period,
        uint256 orderIndex
    );

    event MintClaimRewards(
        address indexed user,
        uint256 orderIndex,
        uint256 amount,
        uint256 inviterBonus
    );

    event StakeEvent(
        address indexed user,
        uint256 xfiAmount,
        uint8 period,
        uint256 orderIndex
    );

    event StakeClaimRewards(
        address indexed user,
        uint256 orderIndex,
        uint256 amount,
        uint256 inviterBonus
    );

    event StakeWithdraw(
        address indexed user,
        uint256 orderIndex,
        uint256 amount
    );

    event InviterSet(address indexed user, address indexed inviter);

    // ============== Modifier ==============

    modifier validMintOrder(address user, uint256 orderIndex) {
        require(
            orderIndex < userMintOrders[user].length,
            "Invalid mint order index"
        );
        require(
            userMintOrders[user][orderIndex].isActive,
            "Mint order is not active"
        );
        _;
    }

    modifier validStakeOrder(address user, uint256 orderIndex) {
        require(
            orderIndex < userStakeOrders[user].length,
            "Invalid stake order index"
        );
        require(
            userStakeOrders[user][orderIndex].isActive,
            "Stake order is not active"
        );
        _;
    }

    modifier validFluxOrder(address user, uint256 orderIndex) {
        require(
            orderIndex < userFluxOrders[user].length,
            "Invalid flux order index"
        );
        require(
            userFluxOrders[user][orderIndex].isActive,
            "Flux order is not active"
        );
        _;
    }

    // ============== Constructor ==============

    constructor() Ownable(msg.sender) {
        xfi = IERC20(0xfAd9152B792679C47Ed4471125A74D041142D53a);
        usdt = IERC20(0x55d398326f99059fF775485246999027B3197955);
        router = IUniswapV2Router(0x10ED43C718714eb63d5aA57B78B54704E256024E);
        xfiUsdtPair = IUniswapV2Pair(0xBA57e276AaF6B3fd5fFc0C2A53fcb751ca824A58);
        
        treasuryAddress = 0xD828687Eb4f0c6caE6d45677f4Eff3F9D8D13AC2;
        marketAddress = 0x7faB38030685e1c33d0E056c2CbAe44CeBdd4854;
        mintReceiveAddress = 0xAdF0Beb27399EbC5C4D70eac0758CEd537F7FCB2;
        burnAddress = 0x000000000000000000000000000000000000dEaD;

        
        mintPeriodConfigs[30] = PeriodConfig(30, 1050); // 30 1.05
        mintPeriodConfigs[60] = PeriodConfig(60, 1100); // 60 1.1
        mintPeriodConfigs[180] = PeriodConfig(180, 1200); // 180 1.2
        mintPeriodConfigs[360] = PeriodConfig(360, 1500); // 360 1.5

        stakeDailyRates[15] = 20; // 15 0.2% -> 20/10000
        stakeDailyRates[30] = 30; // 30 0.3% -> 30/10000
        stakeDailyRates[90] = 40; // 90 0.4% -> 40/10000
        stakeDailyRates[180] = 50; // 180 0.5% -> 50/10000
        stakeDailyRates[360] = 60; // 360 0.6% -> 60/10000
    }

    // ============== Administrator Functions ==============

    function setAddresses(
        address _treasury,
        address _market,
        address _mintReceiveAddress
    ) external onlyOwner {
        treasuryAddress = _treasury;
        marketAddress = _market;
        mintReceiveAddress = _mintReceiveAddress;
    }

    function setXfi(address _xfi) external onlyOwner {
        xfi = IERC20(_xfi);
    }

    function withdrawalToken(
        address to,
        address token,
        uint256 amount
    ) external onlyOwner {
        IERC20(token).transfer(to, amount);
    }

    // ============== Invitation System ==============

    /**
     * Binding superior inviter
     */
    function bindInviter(address inviter) external {
        require(inviter != msg.sender, "Cannot invite yourself");
        require(inviterMap[msg.sender] == address(0), "Inviter already bound");
        inviterMap[msg.sender] = inviter;
        emit InviterSet(msg.sender, inviter);
    }

    /**
     * Obtain user invitation relationship information
     */
    function getInviterInfo(
        address user
    ) external view returns (address inviter, bool hasValid) {
        inviter = inviterMap[user];
        hasValid = hasValidOrder[user];
    }

    /**
     * Internal function for handling invitation rebates
     */
    function _processInviterBonus(
        address user,
        uint256 rewardAmount
    ) internal returns (uint256) {
        address userInviter = inviterMap[user];
        if (userInviter != address(0) && hasValidOrder[userInviter]) {
            uint256 inviterBonus = Math.mulDiv(
                rewardAmount,
                INVITER_BONUS_RATE,
                PERCENT_BASE
            );
            require(
                xfi.transfer(userInviter, inviterBonus),
                "Inviter bonus transfer failed"
            );
            return inviterBonus;
        }
        return 0;
    }

    // ============== General Price Inquiry ==============

    function getCurrentXFIPrice() public view returns (uint256) {
        address[] memory path = new address[](2);
        path[0] = address(xfi);
        path[1] = address(usdt);

        try router.getAmountsOut(1e18, path) returns (
            uint256[] memory amounts
        ) {
            require(
                amounts.length == 2 && amounts[1] > 0,
                "Invalid price data"
            );
            return amounts[1];
        } catch {
            revert("Unable to get XFI price");
        }
    }

    function calculateUSDTRequired(
        uint256 xfiAmount
    ) public view returns (uint256) {
        address[] memory path = new address[](2);
        path[0] = address(usdt);
        path[1] = address(xfi);

        try router.getAmountsIn(xfiAmount, path) returns (
            uint256[] memory amounts
        ) {
            require(
                amounts.length == 2 && amounts[0] > 0,
                "Invalid price data"
            );
            return amounts[0];
        } catch {
            revert("Unable to calculate USDT required");
        }
    }



    /**
     * Create Flux order (internal function)
     */
    function _createFluxOrder(
        address user,
        uint256 xfiAmount,
        string memory source
    ) internal returns (uint256) {
        FluxOrder memory newOrder = FluxOrder({
            user: user,
            xfiAmount: xfiAmount,
            usdtPaid: 0,
            createTime: block.timestamp,
            unlockTime: block.timestamp + FLUX_HOLDING_PERIOD,
            isActive: true,
            isClaimed: false,
            source: source
        });

        userFluxOrders[user].push(newOrder);
        uint256 orderIndex = userFluxOrders[user].length - 1;

        uint256 usdtRequired = calculateUSDTRequired(xfiAmount);

        emit FluxOrderCreated(
            user,
            orderIndex,
            xfiAmount,
            usdtRequired,
            source
        );

        return orderIndex;
    }

    /**
     * User pays USDT to complete Flux purchase
     */
    function payForFluxSwap(
        uint256 orderIndex
    ) external nonReentrant validFluxOrder(msg.sender, orderIndex) {
        FluxOrder storage order = userFluxOrders[msg.sender][orderIndex];
        require(order.usdtPaid == 0, "Order already paid");

        uint256 usdtRequired = calculateUSDTRequired(order.xfiAmount);

        require(
            usdt.transferFrom(msg.sender, address(this), usdtRequired),
            "USDT transfer failed"
        );

        order.usdtPaid = usdtRequired;

        _swapUSDTForXFI(usdtRequired);

        emit FluxOrderPaid(msg.sender, orderIndex, usdtRequired);
    }

    /**
     * Buy XFI with USDT to user address
     */
    function _swapUSDTForXFI(uint256 usdtAmount) internal {
        address[] memory path = new address[](2);
        path[0] = address(usdt);
        path[1] = address(xfi);

        require(
            usdt.approve(address(router), usdtAmount),
            "USDT approve failed"
        );

        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            usdtAmount,
            0,
            path,
            msg.sender,
            block.timestamp + 300
        );
    }

    /**
     * Create Flux order and pay immediately (internal function)
     */
    function _createAndPayFluxOrder(
        address user,
        uint256 xfiAmount,
        string memory source
    ) internal returns (uint256) {
        uint256 usdtRequired = calculateUSDTRequired(xfiAmount);
        
        require(
            usdt.transferFrom(user, address(this), usdtRequired),
            "USDT transfer failed"
        );

         _swapUSDTForXFI(usdtRequired);

        FluxOrder memory newOrder = FluxOrder({
            user: user,
            xfiAmount: xfiAmount,
            usdtPaid: usdtRequired,
            createTime: block.timestamp,
            unlockTime: block.timestamp + FLUX_HOLDING_PERIOD,
            isActive: true,
            isClaimed: false,
            source: source
        });

        userFluxOrders[user].push(newOrder);
        uint256 orderIndex = userFluxOrders[user].length - 1;

        emit FluxOrderCreated(
            user,
            orderIndex,
            xfiAmount,
            usdtRequired,
            source
        );

        emit FluxOrderPaid(user, orderIndex, usdtRequired);

        return orderIndex;
    }

    /**
     * User receives XFI Reward at the end of rest period
     */
    function claimFluxReward(
        uint256 orderIndex
    ) external nonReentrant validFluxOrder(msg.sender, orderIndex) {
        FluxOrder storage order = userFluxOrders[msg.sender][orderIndex];

        require(order.usdtPaid > 0, "Order not paid");
        require(!order.isClaimed, "Reward already claimed");
        require(
            block.timestamp >= order.unlockTime,
            "Holding period not finished"
        );

        order.isClaimed = true;
        order.isActive = false;

        require(
            xfi.transfer(msg.sender, order.xfiAmount),
            "XFI transfer failed"
        );

        emit FluxRewardClaimed(msg.sender, orderIndex, order.xfiAmount);
    }

    /**
     * Get user Flux order quantity
     */
    function getUserFluxOrderCount(
        address user
    ) external view returns (uint256) {
        return userFluxOrders[user].length;
    }

    /**
     * Get user Flux order details
     */
    function getFluxOrderInfo(
        address user,
        uint256 orderIndex
    )
        external
        view
        returns (
            uint256 xfiAmount,
            uint256 usdtPaid,
            uint256 createTime,
            uint256 unlockTime,
            uint256 remainingTime,
            bool isActive,
            bool isClaimed,
            bool canClaim,
            string memory source
        )
    {
        FluxOrder memory order = userFluxOrders[user][orderIndex];
        return (
            order.xfiAmount,
            order.usdtPaid,
            order.createTime,
            order.unlockTime,
            block.timestamp >= order.unlockTime
                ? 0
                : order.unlockTime - block.timestamp,
            order.isActive,
            order.isClaimed,
            (order.usdtPaid > 0) &&
                !order.isClaimed &&
                (block.timestamp >= order.unlockTime),
            order.source
        );
    }

    // ============== Coin Module Ribbon ==============

    /**
     * Calculate the current mint price
     * Rule: For every 3USDT increase in XFI price, the mint price will be 1USDT.
     */
    function getMintPrice() public view returns (uint256) {
        uint256 xfiPrice = getCurrentXFIPrice();

        if (xfiPrice < 6 * 1e18) {
            return 1;
        }

        return Math.mulDiv(xfiPrice, 1, 3 * 1e18);
    }

    /**
     * Calculate the number of coins based on the USDT amount
     */
    function calculateMintAmount(
        uint256 usdtAmount
    ) public view returns (uint256) {
        uint256 mintPrice = getMintPrice();
        return Math.mulDiv(usdtAmount, 1, mintPrice);
    }

    /**
     * Calculate the total amount of XFI rewards available to the user
     */
    function calculateXFIReward(
        uint256 usdtAmount,
        uint8 period
    ) public view returns (uint256) {
        require(mintPeriodConfigs[period].daysTime > 0, "Invalid period");

        uint256 xfiPrice = getCurrentXFIPrice();

        uint256 multiplier = mintPeriodConfigs[period].multiplier;
        return Math.mulDiv(
            usdtAmount * multiplier * 1e18,
            1,
            xfiPrice * MULTIPLIER_BASE
        );
    }

    /**
     * Coin core function
     */
    function mint(uint256 usdtAmount, uint8 period) external nonReentrant {
        require(usdtAmount >= MIN_MINT_AMOUNT, "Amount too small");
        require(usdtAmount % (10 * 1e18) == 0, "Amount must be multiple of 10");
        require(mintPeriodConfigs[period].daysTime > 0, "Invalid period");

        
        uint256 totalSeconds = mintPeriodConfigs[period].daysTime * SECONDS_PER_DAY;

        uint256 xfiReward = calculateXFIReward(usdtAmount, period);
        require(xfiReward > 0, "xfi reward too small");
        uint256 rewardPerSecond = xfiReward / totalSeconds;

        require(
            usdt.transferFrom(msg.sender, address(this), usdtAmount),
            "USDT transfer failed"
        );

        _distributeMintUSDT(usdtAmount);

        uint256 xfiMintCount = calculateMintAmount(usdtAmount);
        _mintAndDistributeXFI(xfiMintCount);

        MintOrder memory newOrder = MintOrder({
            usdtAmount: usdtAmount,
            xfiAmount: xfiReward,
            rewardPerSecond: rewardPerSecond,
            startTime: block.timestamp,
            endTime: block.timestamp + totalSeconds,
            lastClaimTime: block.timestamp,
            totalClaimed: 0,
            period: period,
            isActive: true
        });

        userMintOrders[msg.sender].push(newOrder);
        hasValidOrder[msg.sender] = true;

        uint256 orderIndex = userMintOrders[msg.sender].length - 1;

        emit MintEvent(msg.sender, usdtAmount, xfiReward, period, orderIndex);
    }

    /**
     * Allocate USDT fund flow
     * 30% Purchase XFI Destroy + 30% Treasury Address + 40% Market Value Address
     */
    function _distributeMintUSDT(uint256 amount) internal {
        uint256 burnAmount = Math.mulDiv(amount, 30, 100);
        uint256 treasuryAmount = Math.mulDiv(amount, 30, 100);

        _swapUSDTForXFIAndBurn(burnAmount);

        require(
            usdt.transfer(treasuryAddress, treasuryAmount),
            "Treasury transfer failed"
        );
        require(
            usdt.transfer(marketAddress, amount - burnAmount - treasuryAmount),
            "Market transfer failed"
        );
    }

    /**
     * Purchase XFI with USDT and send to destruction address
     */
    function _swapUSDTForXFIAndBurn(uint256 usdtAmount) internal {
        if (usdtAmount == 0) return;

        address[] memory path = new address[](2);
        path[0] = address(usdt);
        path[1] = address(xfi);

        require(
            usdt.approve(address(router), usdtAmount),
            "USDT approve failed"
        );

        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            usdtAmount,
            0,
            path,
            burnAddress,
            block.timestamp + 300
        );
    }

    /**
     * Cast and distribute XFI tokens
     */
    function _mintAndDistributeXFI(uint256 amount) internal {
        uint256 half = amount / 2;
        xfi.mint(address(this), half);
        xfi.mint(treasuryAddress, amount - half);
    }

    /**
     * Calculate user rewards to be claimed
     */
    function calculateMintRewards(
        address user,
        uint256 orderIndex
    ) public view returns (uint256) {
        MintOrder memory order = userMintOrders[user][orderIndex];

        if (!order.isActive || block.timestamp <= order.lastClaimTime) {
            return 0;
        }

        uint256 currentTime = block.timestamp;
        if (currentTime > order.endTime) {
            currentTime = order.endTime;
        }

        uint256 timeElapsed = currentTime - order.lastClaimTime;
        (bool success, uint256 pendingReward) = Math.tryMul(timeElapsed, order.rewardPerSecond);
        require(success, "Reward calculation overflow");

        uint256 remainingReward = order.xfiAmount - order.totalClaimed;
        pendingReward = Math.min(pendingReward, remainingReward);

        return pendingReward;
    }

    /**
     * Receive single mint order reward (create Flux order directly)
     */
    function claimMintRewards(
        uint256 orderIndex
    ) external nonReentrant validMintOrder(msg.sender, orderIndex) {
        MintOrder storage order = userMintOrders[msg.sender][orderIndex];

        uint256 pendingReward = calculateMintRewards(msg.sender, orderIndex);
        require(pendingReward > 0, "No rewards to claim");

        _createAndPayFluxOrder(msg.sender, pendingReward, "mint");

        order.totalClaimed = order.totalClaimed + pendingReward;
        order.lastClaimTime = block.timestamp;

        uint256 inviterBonus = _processInviterBonus(msg.sender, pendingReward);

        if (
            order.totalClaimed >= order.xfiAmount ||
            block.timestamp >= order.endTime
        ) {
            order.isActive = false;
        }

        emit MintClaimRewards(
            msg.sender,
            orderIndex,
            pendingReward,
            inviterBonus
        );
    }

    function getUserMintOrderCount(
        address user
    ) external view returns (uint256) {
        return userMintOrders[user].length;
    }

    function getMintOrderInfo(
        address user,
        uint256 orderIndex
    )
        external
        view
        returns (
            uint256 usdtAmount,
            uint256 xfiAmount,
            uint256 rewardPerSecond,
            uint256 totalClaimed,
            uint256 lastClaimTime,
            uint256 pendingReward,
            uint256 startTime,
            uint256 endTime,
            uint8 period,
            bool isActive,
            bool isExpired
        )
    {
        MintOrder storage order = userMintOrders[user][orderIndex];
        uint256 reward = calculateMintRewards(user, orderIndex);
        return (
            order.usdtAmount,
            order.xfiAmount,
            order.rewardPerSecond,
            order.totalClaimed,
            order.lastClaimTime,
            reward,
            order.startTime,
            order.endTime,
            order.period,
            order.isActive,
            block.timestamp > order.endTime
        );
    }

    // ============== Pledge module functional area ==============

    /**
     * Pledge core function
     */
    function stake(uint256 xfiAmount, uint8 period) external nonReentrant {
        require(xfiAmount > 0, "Amount must be greater than 0");
        require(stakeDailyRates[period] > 0, "Invalid period");

        require(
            xfi.transferFrom(msg.sender, address(this), xfiAmount),
            "XFI transfer failed"
        );

        uint256 dailyRate = stakeDailyRates[period];
        uint256 rewardPerSecond = Math.mulDiv(xfiAmount, dailyRate, 10000 * SECONDS_PER_DAY);

        StakeOrder memory newOrder = StakeOrder({
            xfiAmount: xfiAmount,
            rewardPerSecond: rewardPerSecond,
            startTime: block.timestamp,
            endTime: block.timestamp + (period * SECONDS_PER_DAY),
            lastClaimTime: block.timestamp,
            totalClaimed: 0,
            period: period,
            dailyRate: dailyRate,
            isActive: true,
            canWithdraw: false
        });

        userStakeOrders[msg.sender].push(newOrder);
        hasValidOrder[msg.sender] = true;

        uint256 orderIndex = userStakeOrders[msg.sender].length - 1;

        emit StakeEvent(msg.sender, xfiAmount, period, orderIndex);
    }

    /**
     * Calculate pledge reward
     */
    function calculateStakeRewards(StakeOrder memory order) public view returns (uint256) {
        if (!order.isActive || block.timestamp <= order.lastClaimTime) {
            return 0;
        }

        if (order.lastClaimTime >= order.endTime) {
            return 0;
        }

        uint256 currentTime = block.timestamp;
        if (currentTime > order.endTime) {
            currentTime = order.endTime;
        }

        uint256 timeElapsed = currentTime - order.lastClaimTime;
        (bool success, uint256 pendingReward) = Math.tryMul(timeElapsed, order.rewardPerSecond);
        require(success, "Reward calculation overflow");

        return pendingReward;
    }

    /**
     * Calculate pledge reward
     */
    function calculateStakeRewards(
        address user,
        uint256 orderIndex
    ) external view returns (uint256) {
        StakeOrder memory order = userStakeOrders[user][orderIndex];
        return calculateStakeRewards(order);
    }

    /**
     * Receive single pledge order reward (directly create Flux order)
     */
    function claimStakeRewards(
        uint256 orderIndex
    ) external nonReentrant validStakeOrder(msg.sender, orderIndex) {
        StakeOrder storage order = userStakeOrders[msg.sender][orderIndex];

        uint256 pendingReward = calculateStakeRewards(order);
        require(pendingReward > 0, "No rewards to claim");

        _createAndPayFluxOrder(msg.sender, pendingReward, "stake");

        order.totalClaimed = order.totalClaimed + pendingReward;
        order.lastClaimTime = block.timestamp;

        if (block.timestamp >= order.endTime) {
            order.canWithdraw = true;
        }

        uint256 inviterBonus = _processInviterBonus(msg.sender, pendingReward);

        emit StakeClaimRewards(
            msg.sender,
            orderIndex,
            pendingReward,
            inviterBonus
        );
    }

    /**
     * Withdrawal of pledged principal (all rewards must be collected first)
     */
    function withdrawStake(
        uint256 orderIndex
    ) external nonReentrant validStakeOrder(msg.sender, orderIndex) {
        StakeOrder storage order = userStakeOrders[msg.sender][orderIndex];

        uint256 pendingReward = calculateStakeRewards(order);
        require(pendingReward == 0, "Please claim all rewards first");
        
        require(order.canWithdraw, "Cannot withdraw yet, please claim rewards first");

        uint256 stakeAmount = order.xfiAmount;

        require(xfi.balanceOf(address(this)) >= stakeAmount, "Contract XFI balance insufficient");
        order.isActive = false;
        order.canWithdraw = false;

        require(xfi.transfer(msg.sender, stakeAmount), "XFI transfer failed");

        emit StakeWithdraw(msg.sender, orderIndex, stakeAmount);
    }

    /**
     * Obtain the number of user pledge orders.
     */
    function getUserStakeOrderCount(
        address user
    ) external view returns (uint256) {
        return userStakeOrders[user].length;
    }

    function getStakeOrderInfo(
        address user,
        uint256 orderIndex
    )
        external
        view
        returns (
            uint256 xfiAmount,
            uint256 rewardPerSecond,
            uint256 totalClaimed,
            uint256 lastClaimTime,
            uint256 pendingReward,
            uint256 startTime,
            uint256 endTime,
            uint8 period,
            bool isActive,
            bool canWithdraw
        )
    {
        StakeOrder memory order = userStakeOrders[user][orderIndex];
        uint256 reward = calculateStakeRewards(order);
        return (
            order.xfiAmount,
            order.rewardPerSecond,
            order.totalClaimed,
            order.lastClaimTime,
            reward,
            order.startTime,
            order.endTime,
            order.period,
            order.isActive,
            order.canWithdraw
        );
    }
}
