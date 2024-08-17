// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

contract ERC666 is ERC20, Ownable, Pausable, ReentrancyGuard, AccessControl {
    // Define a role for fractional owners
    bytes32 public constant FRACTIONAL_OWNER_ROLE = keccak256("FRACTIONAL_OWNER_ROLE");

    // Store asset details
    string private _assetDetails;

    // Manage fractional ownership
    address[] private _fractionalOwners;
    mapping(address => uint256) private _fractions;
    mapping(address => uint256) private _stakedBalances;
    mapping(address => uint256) private _stakingRewards;
    uint256 private _totalStaked;

    // Interface for ERC-1155 contract
    IERC1155 private _erc1155Contract;

    // Events to log important actions
    event FractionalOwnerAdded(address indexed owner, uint256 fraction);
    event FractionalOwnerRemoved(address indexed owner);
    event Staked(address indexed owner, uint256 amount, uint256 timestamp);
    event Unstaked(address indexed owner, uint256 amount, uint256 timestamp);
    event RewardPaid(address indexed owner, uint256 reward);
    event AssetDetailsUpdated(string newDetails);
    event ERC1155TokenDeposited(address indexed owner, uint256 id, uint256 amount);
    event ERC1155TokenWithdrawn(address indexed owner, uint256 id, uint256 amount);

    constructor(
        string memory name,
        string memory symbol,
        string memory initialAssetDetails,
        address erc1155Address
    ) ERC20(name, symbol) Ownable(msg.sender) {
        _assetDetails = initialAssetDetails;
        _erc1155Contract = IERC1155(erc1155Address);
    }

    // Retrieve the asset details
    function getAssetDetails() public view returns (string memory) {
        return _assetDetails;
    }

    // Update the asset details
    function updateAssetDetails(string memory newDetails) public onlyOwner {
        _assetDetails = newDetails;
        emit AssetDetailsUpdated(newDetails);
    }

    // Add a fractional owner with a specified fraction
    function addFractionalOwner(address owner, uint256 fraction) public onlyOwner {
        require(owner != address(0), "Invalid address");
        require(fraction > 0, "Fraction must be positive");
        _fractionalOwners.push(owner);
        _fractions[owner] = fraction;
        grantRole(FRACTIONAL_OWNER_ROLE, owner);
        emit FractionalOwnerAdded(owner, fraction);
    }

    // Remove a fractional owner
    function removeFractionalOwner(address owner) public onlyOwner {
        require(owner != address(0), "Invalid address");
        require(_fractions[owner] > 0, "Owner not found");
        _fractions[owner] = 0;
        revokeRole(FRACTIONAL_OWNER_ROLE, owner);
        emit FractionalOwnerRemoved(owner);
    }

    // Get the list of all fractional owners
    function getFractionalOwners() public view returns (address[] memory) {
        return _fractionalOwners;
    }

    // Get the fraction owned by a specific address
    function getFractionOf(address owner) public view returns (uint256) {
        return _fractions[owner];
    }

    // Staking functionality: Stake a specified amount
    function stake(uint256 amount) public whenNotPaused nonReentrant {
        require(amount > 0, "Cannot stake 0");
        _burn(msg.sender, amount); // Burn the staked tokens
        _stakedBalances[msg.sender] += amount;
        _totalStaked += amount;
        emit Staked(msg.sender, amount, block.timestamp);
    }

    // Unstaking functionality: Unstake a specified amount
    function unstake(uint256 amount) public whenNotPaused nonReentrant {
        require(amount > 0, "Cannot unstake 0");
        require(_stakedBalances[msg.sender] >= amount, "Insufficient staked balance");
        _stakedBalances[msg.sender] -= amount;
        _totalStaked -= amount;
        _mint(msg.sender, amount); // Mint unstaked tokens back to the user
        emit Unstaked(msg.sender, amount, block.timestamp);
    }

    // Retrieve the staked balance of a specific address
    function stakedBalanceOf(address owner) public view returns (uint256) {
        return _stakedBalances[owner];
    }

    // Retrieve the total amount of staked tokens
    function totalStaked() public view returns (uint256) {
        return _totalStaked;
    }

    // Distribute rewards to stakers based on their staked amount
    function distributeRewards(uint256 rewardAmount) public onlyOwner {
        require(_totalStaked > 0, "No staked tokens");
        for (uint i = 0; i < _fractionalOwners.length; i++) {
            address owner = _fractionalOwners[i];
            if (_stakedBalances[owner] > 0) {
                uint256 reward = rewardAmount * _stakedBalances[owner] / _totalStaked;
                _stakingRewards[owner] += reward;
            }
        }
    }

    // Claim the staking rewards for the sender
    function claimReward() public whenNotPaused nonReentrant {
        uint256 reward = _stakingRewards[msg.sender];
        require(reward > 0, "No rewards to claim");
        _stakingRewards[msg.sender] = 0;
        _mint(msg.sender, reward); // Mint reward tokens to the user
        emit RewardPaid(msg.sender, reward);
    }

    // Retrieve the staking rewards for a specific address
    function stakingRewardsOf(address owner) public view returns (uint256) {
        return _stakingRewards[owner];
    }

    // Pausable functionality: Pause the contract
    function pause() public onlyOwner {
        _pause();
    }

    // Pausable functionality: Unpause the contract
    function unpause() public onlyOwner {
        _unpause();
    }

    // Override transfer functions to ensure they are paused if the contract is paused
    function transfer(address recipient, uint256 amount) public override whenNotPaused returns (bool) {
        return super.transfer(recipient, amount);
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override whenNotPaused returns (bool) {
        return super.transferFrom(sender, recipient, amount);
    }

    // Deposit ERC-1155 tokens into the contract
    function depositERC1155Token(uint256 id, uint256 amount) public whenNotPaused nonReentrant {
        require(amount > 0, "Cannot deposit 0");
        _erc1155Contract.safeTransferFrom(msg.sender, address(this), id, amount, "");
        emit ERC1155TokenDeposited(msg.sender, id, amount);
    }

    // Withdraw ERC-1155 tokens from the contract
    function withdrawERC1155Token(uint256 id, uint256 amount) public whenNotPaused nonReentrant {
        require(amount > 0, "Cannot withdraw 0");
        _erc1155Contract.safeTransferFrom(address(this), msg.sender, id, amount, "");
        emit ERC1155TokenWithdrawn(msg.sender, id, amount);
    }
}
