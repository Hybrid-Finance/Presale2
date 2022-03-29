// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.7.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


contract HyFi is ERC20, Ownable {
    using SafeMath for uint256;
    
    address public presale;
    address public burner;
    mapping(address => bool) public whitelisted;
    uint public constant presaleSupply = 913_000e18;
    uint public constant initSupply = 1833333e16;

    modifier onlyBurner() {
        require(msg.sender == burner, "Cannot burn");
        _;
    }

    constructor(address _daoWallet) ERC20("HyFi", "HyFi") {
        whitelisted[_daoWallet] = true;
        _mint(_daoWallet, initSupply);
    }

    function setPresale(address _presale) external onlyOwner {
        require(_presale != address(0), "Cannot be zero address");
        require(presale == address(0), "Already set");
        presale = _presale;
        whitelisted[presale] = true;
        _mint(presale, presaleSupply);
    }

    function setBurner(address _burner) external onlyOwner {
        require(_burner != address(0), "Cannot be zero address");
        burner = _burner;
        whitelisted[burner] = true;
    }

    function setWhitelist(address _address, bool _status) external onlyOwner {
        require(_address != address(0), "Cannot be zero address");
        whitelisted[_address] = _status;
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    function burnFrom(address account, uint256 amount) external onlyBurner {
        uint256 decreasedAllowance = allowance(account, msg.sender).sub(amount, "ERC20: burn amount exceeds allowance");
        _approve(account, msg.sender, decreasedAllowance);
        _burn(account, amount);
    }

    function _beforeTokenTransfer(address from, address to, uint256) internal virtual override {
        require(whitelisted[to] || whitelisted[from] || to == address(0), "Not whitelisted");
    }
}