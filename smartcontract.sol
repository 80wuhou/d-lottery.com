// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract DeLotGame is ERC20, ReentrancyGuard {
    struct TransferRecord {
        uint256 amount;
        uint256 triggerBlock;
        bytes userData;
    }

    mapping(address => TransferRecord) public transferHistory;
    uint256 private constant MAX_DATA_LENGTH = 16;

    event Minted(address indexed user, uint256 ethAmount, uint256 dltAmount);
    event Redeemed(address indexed user, uint256 dltAmount, uint256 ethAmount);
    event GamePlay(address indexed user, uint256 ethAmount, bytes data, uint256 triggerBlock);
    event RewardSent(address indexed user, uint256 rewardAmount);

    constructor() ERC20("DeLot", "DLT") {}

    receive() external payable nonReentrant {
        _processMint();
    }

    fallback() external payable nonReentrant {
        _processGame(msg.sender, msg.data);
    }

    function _processMint() private {
        uint256 ethAmount = msg.value;
        uint256 contractEth = address(this).balance - ethAmount; // 排除当前转入的ETH
        uint256 totalDLT = totalSupply();

        uint256 mintAmount = totalDLT == 0 ? ethAmount : 
            contractEth <= totalDLT ? ethAmount : 
            (ethAmount * totalDLT) / contractEth;

        _mint(msg.sender, mintAmount);
        emit Minted(msg.sender, ethAmount, mintAmount);
    }

    function _processGame(address sender, bytes memory data) private {
        require(msg.value > 0, "Must send ETH to play");
        
        TransferRecord memory last = transferHistory[sender];
        bytes memory cleanData = _sanitizeData(data);
        require(cleanData.length > 0, "Invalid game data");

        if (last.triggerBlock != 0) {
            uint256 targetBlock = _nextRoundNumber(last.triggerBlock);
            
            if (block.number > targetBlock && 
                block.number - targetBlock <= 256) 
            {
                bytes32 targetHash = blockhash(targetBlock);
                
                if (targetHash != 0 && 
                    _hasMatchingChar(last.userData, _getLastChar(targetHash)))
                {
                    _sendReward(sender, last.amount, last.userData.length);
                }
            }
        }

        transferHistory[sender] = TransferRecord(
            msg.value,
            block.number,
            cleanData
        );
        emit GamePlay(sender, msg.value, cleanData, block.number);
    }

    function redeem(uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must > 0");
        uint256 totalDLT = totalSupply();
        require(totalDLT > 0, "No DLT in circulation");

        uint256 ethAmount = (amount * address(this).balance) / totalDLT;
        require(ethAmount > 0, "Insufficient ETH");

        _burn(msg.sender, amount);
        payable(msg.sender).transfer(ethAmount);
        emit Redeemed(msg.sender, amount, ethAmount);
    }

    function transfer(address to, uint256 amount) public override nonReentrant returns (bool) {
        if (to == address(this)) {
            _autoRedeem(msg.sender, amount);
            return true;
        }
        return super.transfer(to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) public override nonReentrant returns (bool) {
        if (to == address(this)) {
            _autoRedeem(from, amount);
            return true;
        }
        return super.transferFrom(from, to, amount);
    }

    function _autoRedeem(address from, uint256 amount) private {
        require(amount > 0, "Amount must > 0");
        uint256 totalDLT = totalSupply();
        require(totalDLT > 0, "No DLT in circulation");

        uint256 ethAmount = (amount * address(this).balance) / totalDLT;
        require(ethAmount > 0, "Insufficient ETH");

        _burn(from, amount);
        payable(from).transfer(ethAmount);
        emit Redeemed(from, amount, ethAmount);
    }

    function _sendReward(address to, uint256 lastAmount, uint256 dataLength) private {
        uint256 reward = (lastAmount * 16 * 9) / (dataLength * 10);
        reward = address(this).balance < reward ? address(this).balance : reward;
        payable(to).transfer(reward);
        emit RewardSent(to, reward);
    }

    function _hasMatchingChar(bytes memory data, bytes1 target) private pure returns (bool) {
        for (uint i = 0; i < data.length; i++) {
            if (data[i] == target) return true;
        }
        return false;
    }

    function _nextRoundNumber(uint256 n) internal pure returns (uint256) {
        return n + (10 - (n % 10));
    }

    function _sanitizeData(bytes memory data) internal pure returns (bytes memory) {
        uint start = 0;
        if (data.length >= 2 && data[0] == 0x30 && data[1] == 0x78) {
            start = 2;
        }
        uint byteLength = data.length - start;
        require(byteLength * 2 <= MAX_DATA_LENGTH, "Data overflow");

        bytes memory cleaned = new bytes(byteLength * 2);
        for (uint i = start; i < data.length; i++) {
            bytes1 b = data[i];
            cleaned[(i - start)*2] = _nibbleToChar(uint8(b) >> 4);
            cleaned[(i - start)*2 + 1] = _nibbleToChar(uint8(b) & 0x0F);
        }
        return cleaned;
    }

    function _getLastChar(bytes32 hash) internal pure returns (bytes1) {
        uint8 lowNibble = uint8(hash[31]) & 0x0F;
        return _nibbleToChar(lowNibble);
    }

    function _nibbleToChar(uint8 nibble) internal pure returns (bytes1) {
        require(nibble < 16, "Invalid nibble");
        return nibble < 10 ? bytes1(nibble + 48) : bytes1(nibble + 87);
    }
}