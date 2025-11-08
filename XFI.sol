// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;
interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount)
        external
        returns (bool);
    function allowance(address owner, address spender)
        external
        view
        returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
}

abstract contract Ownable {
    address private _owner;
    address private _previousOwner;
    uint256 private _lockTime;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor ()  {
        address msgSender = msg.sender;
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    function owner() public view returns (address) {
        return _owner;
    }   
    
    modifier onlyOwner() {
        require(_owner == msg.sender, "Ownable: caller is not the owner");
        _;
    }
    
    function renounceOwnership() public virtual onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

library SafeMath {
    /**
     * @dev Returns the addition of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `+` operator.
     *
     * Requirements:
     *
     * - Addition cannot overflow.
     */
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");

        return c;
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting on
     * overflow (when the result is negative).
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     *
     * - Subtraction cannot overflow.
     */
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return sub(a, b, "SafeMath: subtraction overflow");
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting with custom message on
     * overflow (when the result is negative).
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     *
     * - Subtraction cannot overflow.
     */
    function sub(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        uint256 c = a - b;

        return c;
    }

    /**
     * @dev Returns the multiplication of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `*` operator.
     *
     * Requirements:
     *
     * - Multiplication cannot overflow.
     */
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
        // benefit is lost if 'b' is also tested.
        // See: https://github.com/OpenZeppelin/openzeppelin-contracts/pull/522
        if (a == 0) {
            return 0;
        }

        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");

        return c;
    }

    /**
     * @dev Returns the integer division of two unsigned integers. Reverts on
     * division by zero. The result is rounded towards zero.
     *
     * Counterpart to Solidity's `/` operator. Note: this function uses a
     * `revert` opcode (which leaves remaining gas untouched) while Solidity
     * uses an invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return div(a, b, "SafeMath: division by zero");
    }

    /**
     * @dev Returns the integer division of two unsigned integers. Reverts with custom message on
     * division by zero. The result is rounded towards zero.
     *
     * Counterpart to Solidity's `/` operator. Note: this function uses a
     * `revert` opcode (which leaves remaining gas untouched) while Solidity
     * uses an invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function div(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        require(b > 0, errorMessage);
        uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold

        return c;
    }
}

interface IUniswapV2Factory {
    function getPair(address tokenA, address tokenB)
        external
        view
        returns (address pair);

    function createPair(address tokenA, address tokenB)
        external
        returns (address pair);
}


interface IUniswapV2Router01 {
    function factory() external pure returns (address);
}

interface Burning {
    function burning(uint256 amount) external;
    function ad() external view returns (address ad);
}


contract XFI is IERC20, Ownable {
    using SafeMath for uint256;

    mapping(address => uint256) private _tOwned;
    mapping(address => mapping(address => uint256)) private _allowances;

    mapping (address => bool) public isDividendExempt;

    mapping(address => bool) public _isExcludedFromFee;
    mapping(address => bool) public _updated;
    
    uint256 private _tFeeTotal;
    string private _name = "XFI";
    string private _symbol = "XFI";
    uint8 private _decimals = 18;

	//on Exchange 1%
    uint256 public _s1Fee = 10;
    address public s1Address;
    //node 1%
    uint256 public _s2Fee = 10;
    address public s2Address;
	//Destroy 1%
    uint256 public _xhFee = 10;
    uint256 public buyAndSell = 30;

    // Locking address
    address public teamVestingAddress;
    address public investorVestingAddress;

    uint256 private _tTotal = 30000000 * 10**18;
    uint256 private _maxTotal = 200000000 * 10**18;
    
    uint256 private _maxMintable = 140000000 * 10**18;  // mint function maximum castable quantity
    uint256 private _maxVesting = 30000000 * 10**18;    // Maximum castable quantity of lock bin
    uint256 private _totalMinted = 0;                   // mint function Cast quantity
    uint256 private _totalVestingMinted = 0;            // Cast quantity of lock bin

    struct VestingInfo {
        uint256 totalAmount;      // Total Locking Volume
        uint256 releasedAmount;   // Released amount
        uint256 startTime;        // Start Time
        uint256 lockPeriod;       // Locking period (seconds)
        uint256 releasePeriod;    // Release period (seconds)
        uint256 releasePercent;   // Percentage of each release (base 1 000,100 = 10%)
        bool isActive;            // Activate or not
    }
    mapping(address => VestingInfo) public vestingInfo;
    
    uint256 private constant SECONDS_PER_YEAR = 31536000;   // 365 * 24 * 60 * 60
    uint256 private constant SECONDS_PER_QUARTER = 7776000; // 90 * 24 * 60 * 60

    IUniswapV2Router01 public immutable uniswapV2Router;
    address public immutable uniswapV2Pair;
    Burning public burningContract;

    bool public isSwap = true;
    mapping(address => bool) public whitelist;
    mapping(address => bool) public mintWhiteList;

    bool inSwapAndLiquify;
    modifier lockTheSwap() {
        inSwapAndLiquify = true;
        _;
        inSwapAndLiquify = false;
    }

    event NodeFee(address node, uint amount, uint typeid);
    event VestingSet(address indexed beneficiary, uint256 amount, uint256 lockPeriod, uint256 releasePercent);
    event TokensReleased(address indexed beneficiary, uint256 amount);
    
    constructor() {
        IUniswapV2Router01 _uniswapV1Router = IUniswapV2Router01(0x10ED43C718714eb63d5aA57B78B54704E256024E);

        // Create a uniswap pair for this new token
        uniswapV2Pair = IUniswapV2Factory(_uniswapV1Router.factory()).createPair(address(this), address(0x55d398326f99059fF775485246999027B3197955));

        // set the rest of the contract variables
        uniswapV2Router = _uniswapV1Router;

        _isExcludedFromFee[msg.sender] = true;
        _isExcludedFromFee[address(this)] = true;
        _isExcludedFromFee[address(_uniswapV1Router)] = true;

        s1Address = 0xb1c4889A4486aADede1a07530e48FFf6056c6419;
        s2Address = 0x16e25609170A0093Ee727d915C7b84A1Da5Fa584;

        _tOwned[0x150D3e5aeBB0B616C0ca15b15A22aa790b34b378] = 10000000 * 10**18;
        emit Transfer(address(0), 0x150D3e5aeBB0B616C0ca15b15A22aa790b34b378, 10000000 * 10**18);

        _tOwned[0x94078657DB8222ECBA682909eFAbdeae2ac4a8f5] = 20000000 * 10**18;
        emit Transfer(address(0), 0x94078657DB8222ECBA682909eFAbdeae2ac4a8f5, 20000000 * 10**18);

        setTeamVesting(0xdacD67d2F683E9E52C65c092f50CC71791D3beF5);
        setInvestorVesting(0x70d2cBE4b1616DC74908b9996FdAD62B1F647383);
    }


    /**
     * @dev Set up technical team lock-up (5%, 2-year lock-up, 10% quarterly release)
     */
    function setTeamVesting(address teamAddress) private {
        require(teamAddress != address(0), "Team address cannot be zero");
        teamVestingAddress = teamAddress;
        uint256 teamAmount = 10000000 * 10**18; // 10,000,000 tokens
        
        vestingInfo[teamAddress] = VestingInfo({
            totalAmount: teamAmount,
            releasedAmount: 0,
            startTime: block.timestamp,
            lockPeriod: 2 * SECONDS_PER_YEAR,    // 2Year = 63,072,000秒
            releasePeriod: SECONDS_PER_QUARTER,  // 90Day = 7,776,000秒
            releasePercent: 100,                 // 10%
            isActive: true
        });
        
        emit VestingSet(teamAddress, teamAmount, 2 * SECONDS_PER_YEAR, 100);
    }
    
    /**
     * @dev 设置投资机构锁仓 (10%, 3年锁仓，每季度释放10%)
     */
    function setInvestorVesting(address investorAddress) private {
        require(investorAddress != address(0), "Investor address cannot be zero");
        investorVestingAddress = investorAddress;
        uint256 investorAmount = 20000000 * 10**18; 
        
        vestingInfo[investorAddress] = VestingInfo({
            totalAmount: investorAmount,
            releasedAmount: 0,
            startTime: block.timestamp,
            lockPeriod: 3 * SECONDS_PER_YEAR,    // 3Year = 94,608,000秒
            releasePeriod: SECONDS_PER_QUARTER,  // 90Day = 7,776,000秒
            releasePercent: 100,                 // 10%
            isActive: true
        });
        
        emit VestingSet(investorAddress, investorAmount, 3 * SECONDS_PER_YEAR, 100);
    }
    
    
    /**
     * @dev Calculate the number of tokens that can be released
     */
    function calculateReleasableAmount(address beneficiary) public view returns (uint256) {
        VestingInfo memory vesting = vestingInfo[beneficiary];
        
        if (!vesting.isActive || vesting.totalAmount == 0) {
            return 0;
        }
        
        if (block.timestamp < vesting.startTime.add(vesting.lockPeriod)) {
            return 0;
        }
        
        uint256 elapsedTime = block.timestamp.sub(vesting.startTime.add(vesting.lockPeriod));
        uint256 releasePeriods = elapsedTime.div(vesting.releasePeriod).add(1);
        
        uint256 totalReleasable = vesting.totalAmount.mul(vesting.releasePercent).mul(releasePeriods).div(1000);
        
        if (totalReleasable > vesting.totalAmount) {
            totalReleasable = vesting.totalAmount;
        }
        
        return totalReleasable.sub(vesting.releasedAmount);
    }
    
    
    /**
     * @dev Trigger lock bin check and automatically cast tokens
     */
    function _triggerVestingRelease(address account) internal {
        VestingInfo storage vesting = vestingInfo[account];
        
    
        if (!vesting.isActive || vesting.totalAmount == 0 || vesting.releasedAmount >= vesting.totalAmount) {
            return;
        }
    
        uint256 releasableAmount = calculateReleasableAmount(account);
        
        if (releasableAmount > 0) {
            uint256 newVestingMinted = _totalVestingMinted.add(releasableAmount);
            if (newVestingMinted > _maxVesting) {
                uint256 remaining = _maxVesting.sub(_totalVestingMinted);
                if (remaining == 0) {
                    return;
                }
                releasableAmount = remaining;
                newVestingMinted = _maxVesting;
            }
            
            uint256 newTotal = _tTotal.add(releasableAmount);
            require(newTotal <= _maxTotal, "Exceeds total supply");
            
            _totalVestingMinted = newVestingMinted;
            _tTotal = newTotal;
            vesting.releasedAmount = vesting.releasedAmount.add(releasableAmount);
            _tOwned[account] = _tOwned[account].add(releasableAmount);
            
            emit Transfer(address(0), account, releasableAmount);
            emit TokensReleased(account, releasableAmount);
        }
    }
    

    function mint(address recipient, uint256 amount) 
        public 
        returns (bool) 
    {
        require(mintWhiteList[msg.sender], "Caller is not whitelisted");
        require(amount > 0, "Amount must be positive");
        
        uint256 newMinted = _totalMinted.add(amount);
        require(newMinted <= _maxMintable, "Exceeds mint quota");
        
        uint256 newTotal = _tTotal.add(amount);
        require(newTotal <= _maxTotal, "Exceeds total supply");
        
        _totalMinted = newMinted;
        _tTotal = newTotal;
        _tOwned[recipient] = _tOwned[recipient].add(amount);
        
        emit Transfer(address(0), recipient, amount);
        return true;
    }

    function setMintWhitelist(address recipient, bool allowed) external onlyOwner {
        mintWhiteList[recipient] = allowed;
    }

    function setBurningAddress(address burningAddress) external onlyOwner {
        burningContract = Burning(burningAddress);
    }

    

    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function decimals() public view returns (uint256) {
        return _decimals;
    }

    function totalSupply() public view override returns (uint256) {
        return _tTotal;
    }

    function maxTotalSupply() public view returns (uint256) {
        return _maxTotal;
    }
    
    function maxMintableSupply() public view returns (uint256) {
        return _maxMintable;
    }
    
    function maxVestingSupply() public view returns (uint256) {
        return _maxVesting;
    }
    
    function totalMinted() public view returns (uint256) {
        return _totalMinted;
    }
    
    function totalVestingMinted() public view returns (uint256) {
        return _totalVestingMinted;
    }
    
    function remainingMintable() public view returns (uint256) {
        return _maxMintable.sub(_totalMinted);
    }
    
    function remainingVesting() public view returns (uint256) {
        return _maxVesting.sub(_totalVestingMinted);
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _tOwned[account];
    }

    function transfer(address recipient, uint256 amount)
        public
        override
        returns (bool)
    {
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    function allowance(address owner, address spender)
        public
        view
        override
        returns (uint256)
    {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount)
        public
        override
        returns (bool)
    {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(
            sender,
            msg.sender,
            _allowances[sender][msg.sender].sub(
                amount,
                "ERC20: transfer amount exceeds allowance"
            )
        );
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue)
        public
        virtual
        returns (bool)
    {
        _approve(
            msg.sender,
            spender,
            _allowances[msg.sender][spender].add(addedValue)
        );
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue)
        public
        virtual
        returns (bool)
    {
        _approve(
            msg.sender,
            spender,
            _allowances[msg.sender][spender].sub(
                subtractedValue,
                "ERC20: decreased allowance below zero"
            )
        );
        return true;
    }

    function totalFees() public view returns (uint256) {
        return _tFeeTotal;
    }

   function isExcludedFromFee(address account) public view returns (bool) {
        return _isExcludedFromFee[account];
    }
    function excludeFromFee(address account) public onlyOwner {
        _isExcludedFromFee[account] = true;
    }

    function includeInFee(address account) public onlyOwner {
        _isExcludedFromFee[account] = false;
    }

    function updateIsSwap(bool _flag) public onlyOwner {
        isSwap = _flag;
    }

    function updateWhitelist(address account,bool _flag) public onlyOwner {
        whitelist[account] = _flag;
    }

    //to recieve ETH from uniswapV2Router when swaping
    receive() external payable {}


    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) private {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) private {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");

        // Check the lock bin
        _triggerVestingRelease(teamVestingAddress);
        _triggerVestingRelease(investorVestingAddress);

        // Burning
        if(address(burningContract) != address(0) && from == burningContract.ad()){
            burningContract.burning(amount);
        }

        //indicates if fee should be deducted from transfer
        bool takeFee = false;

        if( to == address(uniswapV2Pair) || from == address(uniswapV2Pair)){
            takeFee = true;
        }

        //if any account belongs to _isExcludedFromFee account then remove the fee
        if (_isExcludedFromFee[from] || _isExcludedFromFee[to]) {
            takeFee = false;
        }

        if(to == address(uniswapV2Pair) || from == address(uniswapV2Pair)){
            if(isSwap){
                if(!whitelist[from] || !whitelist[to]){
                    require(false,"you are not on the whitelist");
                }
            }
        }
        if(!inSwapAndLiquify){
            _tokenTransfer(from, to, amount, takeFee);
        }
    }


    //this method is responsible for taking all fee, if takeFee is true
    function _tokenTransfer(
        address sender,
        address recipient,
        uint256 tAmount,
        bool takeFee
    ) private lockTheSwap{
     
       _tOwned[sender] = _tOwned[sender].sub(tAmount);
        if(takeFee){
            uint256 fee_lp1 = tAmount * _s1Fee / 1000;
            uint256 fee_lp2 = tAmount * _s2Fee / 1000;
            uint256 fee_xh = tAmount * _xhFee / 1000;

            _tOwned[s1Address] = _tOwned[s1Address].add(fee_lp1);
			emit Transfer(sender, s1Address, fee_lp1);
            _tOwned[s2Address] = _tOwned[s2Address].add(fee_lp2);
		    emit Transfer(sender, s2Address, fee_lp2);

            emit NodeFee(s1Address, fee_lp1, 1);
            emit NodeFee(s2Address, fee_lp2, 2);
            emit NodeFee(0x000000000000000000000000000000000000dEaD, fee_xh, 3);

             _tOwned[0x000000000000000000000000000000000000dEaD] = _tOwned[0x000000000000000000000000000000000000dEaD].add(fee_xh);
			emit Transfer(sender, 0x000000000000000000000000000000000000dEaD, fee_xh);

            uint256 zfee = tAmount * buyAndSell / 1000;
            _tOwned[recipient] = _tOwned[recipient].add(tAmount - zfee);
            emit Transfer(sender, recipient, tAmount - zfee);
        }else{
            _tOwned[recipient] = _tOwned[recipient].add(tAmount);
            emit Transfer(sender, recipient, tAmount);
        }
     
    }
}
