// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.7.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./interfaces/AggregatorV3Interface.sol";
import "./interfaces/IBurnable.sol";


contract Presale is Ownable, Pausable, ReentrancyGuard {
    using SafeMath for uint;
    using SafeERC20 for IERC20;

    event Buy(address indexed user, uint amount, uint tokens, uint time);
    event BuyAvax(address indexed user, uint amount, uint tokens, uint time);
    event HybirdRedeemed(address indexed user, uint amount);
    
    uint public constant tier1Price = 0.80e6;
    uint public constant tier2Price = 0.90e6;
    uint public constant fcfsPrice = 1e6;

    uint public constant tier1Alloc = 1500e18;
    uint public constant tier2Alloc = 1300e18;
    uint public constant fcfsAlloc = 2000e18;
    
    address public immutable hyfi;
    address public immutable usdce;

    uint public presaleStart;
    uint public tier1Deadline;
    uint public tier2Deadline;
    uint public fcfsDeadline;

    uint public convertDeadline;
    
    mapping(address => bool) public whitelistTier1;
    mapping(address => bool) public whitelistTier2;
    mapping(address => bool) public whitelistFcfs;

    mapping(address => uint) public buyTier1;
    mapping(address => uint) public buyTier2;
    mapping(address => uint) public buyFcfs;

    address public treasury;
    address public hybrid;

    AggregatorV3Interface private avaxPriceFeed;

    modifier presaleRunning() {
        require(block.timestamp >= presaleStart, "Not yet started");
        require(block.timestamp <= fcfsDeadline, "presale ended");
        _;
    }
    
    constructor(address _hyfi, address _usdce, address _avaxPriceFeed, address _treasury) {
        require(_hyfi != address(0), "Cannot be zero address");
        require(_usdce != address(0), "Cannot be zero address");
        require(_avaxPriceFeed != address(0), "Cannot be zero address");
        require(_treasury != address(0), "Cannot be zero address");
        hyfi = _hyfi;
        usdce = _usdce;
        avaxPriceFeed = AggregatorV3Interface(_avaxPriceFeed);
        treasury = _treasury;
    }

    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "Cannot be zero address");
        treasury = _treasury;
    }

    function setAvaxPriceFeed(address _avaxPriceFeed) external onlyOwner {
        require(_avaxPriceFeed != address(0), "Cannot be zero address");
        avaxPriceFeed = AggregatorV3Interface(_avaxPriceFeed);
    }

    function setStartTime(uint _presaleStart) external onlyOwner {
        require(_presaleStart > 0, "Cannot be 0");
        presaleStart = _presaleStart;
    }

    function setDeadlines(uint _tier1Deadline, uint _tier2Deadline, uint _fcfsDeadline) external onlyOwner {
        require(_tier1Deadline > 0);
        require(_tier2Deadline > 0);
        require(_fcfsDeadline > 0);
        tier1Deadline = _tier1Deadline;
        tier2Deadline = _tier2Deadline;
        fcfsDeadline = _fcfsDeadline;
    }

    function setHybrid(address _hybrid) external onlyOwner {
        require(_hybrid != address(0), "Cannot be zero address");
        hybrid = _hybrid;
    }

    function setConvertDeadline(uint _convertDeadline) external onlyOwner {
        require(_convertDeadline > 0);
        convertDeadline = _convertDeadline;
    }

    function setWhitelistTier1(address[] memory _accounts, bool _status) external onlyOwner {
        for(uint i=0; i < _accounts.length; i++) {
            whitelistTier1[_accounts[i]] = _status;
        }
    }

    function setWhitelistTier2(address[] memory _accounts, bool _status) external onlyOwner {
        for(uint i=0; i < _accounts.length; i++) {
            whitelistTier2[_accounts[i]] = _status;
        }
    }

    function setWhitelistFcfs(address[] memory _accounts, bool _status) external onlyOwner {
        for(uint i=0; i < _accounts.length; i++) {
            whitelistFcfs[_accounts[i]] = _status;
        }
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function withdraw(address token) external onlyOwner {
        require(token != hybrid || block.timestamp > convertDeadline, "Cannot withdraw hybrid");
        uint amount = IERC20(token).balanceOf(address(this));
        IERC20(token).transfer(treasury, amount);
    }

    function withdrawEth() external onlyOwner {
        safeTransferETH(treasury, address(this).balance);
    }

    function avaxAssetPrice() public view returns (uint) {
        ( , int price, , , ) = avaxPriceFeed.latestRoundData();
        return uint(price);
    }

    function getCurrentPrice() public view returns (uint price) {
        if (block.timestamp < tier1Deadline) {
            price = tier1Price;
        } else if (block.timestamp < tier2Deadline) {
            price = tier2Price;
        } else {
            price = fcfsPrice;
        }
    }

    function checkWhitelist(address user) public view returns (bool) {
        if (block.timestamp < tier1Deadline) {
            return whitelistTier1[user];
        } else if (block.timestamp < tier2Deadline) {
            return whitelistTier2[user];
        } else {
            return whitelistFcfs[user];
        }
    }

    function getRemainingAllocation(address user) public view returns (uint allocRemaining) {
        if (block.timestamp < tier1Deadline) {
            allocRemaining = tier1Alloc.sub(buyTier1[user]);
        } else if (block.timestamp < tier2Deadline) {
            allocRemaining = tier2Alloc.sub(buyTier2[user]);
        } else {
            allocRemaining = fcfsAlloc.sub(buyFcfs[user]);
        }
    }

    function setAllocation(address user, uint numTokens) internal {
        if (block.timestamp < tier1Deadline) {
            uint totalTokens = buyTier1[user].add(numTokens);
            require(totalTokens <= tier1Alloc, "More than allocation");
            buyTier1[user] = totalTokens;
        } else if (block.timestamp < tier2Deadline) {
            uint totalTokens = buyTier2[user].add(numTokens);
            require(totalTokens <= tier2Alloc, "More than allocation");
            buyTier2[user] = totalTokens;
        } else {
            uint totalTokens = buyFcfs[user].add(numTokens);
            require(totalTokens <= fcfsAlloc, "More than allocation");
            buyFcfs[user] = totalTokens;
        }
    }

    function avaxToUSD(uint amount) public view returns (uint) {
        return amount.mul(avaxAssetPrice()).div( 10 ** uint(avaxPriceFeed.decimals()) ).div(1e12);
    }

    function buy(uint amount) external whenNotPaused presaleRunning nonReentrant {
        require(checkWhitelist(msg.sender), "Not whitelisted");
        uint numTokens = getNumTokens(amount);
        
        IERC20(usdce).safeTransferFrom(msg.sender, treasury, amount);
        setAllocation(msg.sender, numTokens);
        IERC20(hyfi).transfer(msg.sender, numTokens);
        emit Buy(msg.sender, amount, numTokens, block.timestamp);
    }

    function buyAvax(uint amountAvax) external payable whenNotPaused presaleRunning nonReentrant {
        require(checkWhitelist(msg.sender), "Not whitelisted");
        require(msg.value == amountAvax, "Amount mismatch");
        uint amount = avaxToUSD(amountAvax);
        uint numTokens = getNumTokens(amount);

        safeTransferETH(treasury, amountAvax);
        setAllocation(msg.sender, numTokens);
        IERC20(hyfi).transfer(msg.sender, numTokens);
        emit BuyAvax(msg.sender, amountAvax, numTokens, block.timestamp);
    }

    function getNumTokens(uint amount) internal view returns (uint numTokens) {
        require(amount >= 50e6, "Too low");
        uint price = getCurrentPrice();
        numTokens = amount.mul(1e18).div(price);
        require(IERC20(hyfi).balanceOf(address(this)) >= numTokens, "Not enough left");
    }

    function convertToHybrid() external whenNotPaused nonReentrant {
        require(block.timestamp <= convertDeadline, "Deadline passed");
        uint amount = IERC20(hyfi).balanceOf(msg.sender);
        require(IERC20(hybrid).balanceOf(address(this)) >= amount, "Not enough left");
        IBurnable(hyfi).burnFrom(msg.sender, amount);
        IERC20(hybrid).transfer(msg.sender, amount);
        emit HybirdRedeemed(msg.sender, amount);
    }

    function safeTransferETH(address to, uint256 value) internal {
        (bool success, ) = to.call{value: value}(new bytes(0));
        require(success, 'STE');
    }
}