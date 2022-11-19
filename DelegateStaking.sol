// SPDX-License-Identifier: MIT
pragma solidity ^0.8.1;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";


/**
 * @dev Interface of the ERC20 standard as defined in the EIP. Does not include
 * the optional functions; to access them see `ERC20Detailed`.
 */
interface IERC20 {
    /**
     * @dev Returns the amount of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves `amount` tokens from the caller's account to `recipient`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a `Transfer` event.
     */
    function transfer(address recipient, uint256 amount) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through `mint`. This is
     * zero by default.
     *
     * This value changes when `mint` are called.
     */
    function mint(address recipient, uint256 amount) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through `burn`. This is
     * zero by default.
     *
     * This value changes when `burn` are called.
     */
    function burn(uint256 amount) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through `transferFrom`. This is
     * zero by default.
     *
     * This value changes when `approve` or `transferFrom` are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits an `Approval` event.
     */
    function approve(address spender, uint256 amount) external returns (bool);

    /**
     * @dev Moves `amount` tokens from `sender` to `recipient` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a `Transfer` event.
     */
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to `approve`. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);
}


// DelegateStaking is the master of THENODE. He can make THENODE and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once THENODE is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract DelegateStaking is Ownable {
    using SafeMath for uint256;

    // Info of each user.
    struct UserInfo {
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        // We do some fancy math here. Basically, any point in time, the amount of THENODEs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accTHENODEPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accTHENODEPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        uint256 allocPoint;       // How many allocation points assigned to this pool. THENODEs to distribute per block.
        uint256 lastRewardBlock;  // Last block number that THENODEs distribution occurs.
        uint256 accTHENODEPerShare; // Accumulated THENODEs per share, times 1e12. See below.
    }

    // Dev address.
    address public devaddr;
    IERC20 public THENODE;
    // THENODE tokens created per block.
    uint256 public THENODEPerBlock;
    // Bonus muliplier for early THENODE makers.
    uint256 public BONUS_MULTIPLIER = 1;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping (uint256 => mapping (address => UserInfo)) public userInfo;
    // Total allocation poitns. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when THENODE mining starts.
    uint256 public startBlock;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    constructor(
        address _devaddr,
        IERC20 _THENODE,
        uint256 _THENODEPerBlock,
        uint256 _startBlock
    ) {
        devaddr = _devaddr;
        THENODE = _THENODE;
        THENODEPerBlock = _THENODEPerBlock;
        startBlock = _startBlock;

        // staking pool
        poolInfo.push(PoolInfo({
            allocPoint: 1000,
            lastRewardBlock: startBlock,
            accTHENODEPerShare: 0
        }));

        totalAllocPoint = 1000;
    }

    function updateMultiplier(uint256 multiplierNumber) public onlyOwner {
        BONUS_MULTIPLIER = multiplierNumber;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(uint256 _allocPoint, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(PoolInfo({
            allocPoint: _allocPoint,
            lastRewardBlock: lastRewardBlock,
            accTHENODEPerShare: 0
        }));
        updateStakingPool();
    }

    // Update the given pool's THENODE allocation point. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        uint256 prevAllocPoint = poolInfo[_pid].allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;
        if (prevAllocPoint != _allocPoint) {
            updateStakingPool();
        }
    }

    function updateStakingPool() internal {
        uint256 length = poolInfo.length;
        uint256 points = 0;
        for (uint256 pid = 1; pid < length; ++pid) {
            points = points.add(poolInfo[pid].allocPoint);
        }
        if (points != 0) {
            points = points.div(3);
            totalAllocPoint = totalAllocPoint.sub(poolInfo[0].allocPoint).add(points);
            poolInfo[0].allocPoint = points;
        }
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        return _to.sub(_from).mul(BONUS_MULTIPLIER);
    }

    // View function to see pending THENODEs on frontend.
    function pendingTHENODE(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accTHENODEPerShare = pool.accTHENODEPerShare;
        uint256 lpSupply = address(this).balance;

        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 THENODEReward = multiplier.mul(THENODEPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accTHENODEPerShare = accTHENODEPerShare.add(THENODEReward.mul(1e12).div(lpSupply));
        }
        return user.amount.mul(accTHENODEPerShare).div(1e12).sub(user.rewardDebt);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }


    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = address(this).balance;
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 THENODEReward = multiplier.mul(THENODEPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
        THENODE.mint(address(this), THENODEReward);
        pool.accTHENODEPerShare = pool.accTHENODEPerShare.add(THENODEReward.mul(1e12).div(lpSupply));
        pool.lastRewardBlock = block.number;
    }

    // Deposit LP tokens to MasterChef for THENODE allocation.
    function deposit(uint256 _pid) public payable {

        require (_pid != 0, 'deposit THENODE by staking');

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accTHENODEPerShare).div(1e12).sub(user.rewardDebt);
            if(pending > 0) {
                safeTHENODETransfer(msg.sender, pending);
            }
        }
        if (msg.value > 0) {
            payable(devaddr).transfer(msg.value / 100);
            user.amount = user.amount.add(msg.value.sub(msg.value / 100));
        }
        user.rewardDebt = user.amount.mul(pool.accTHENODEPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, msg.value);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) public {

        require (_pid != 0, 'withdraw THENODE by unstaking');

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accTHENODEPerShare).div(1e12).sub(user.rewardDebt);
        if(pending > 0) {
            safeTHENODETransfer(msg.sender, pending);
        }
        if(_amount > 0) {
            user.amount = user.amount.sub(_amount);
            payable(devaddr).transfer(_amount / 100);
            payable(msg.sender).transfer(_amount.sub(_amount / 100));
        }
        user.rewardDebt = user.amount.mul(pool.accTHENODEPerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Stake THENODE tokens to MasterChef
    function enterStaking(uint256 _amount) public payable {
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[0][msg.sender];
        updatePool(0);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accTHENODEPerShare).div(1e12).sub(user.rewardDebt);
            if(pending > 0) {
                safeTHENODETransfer(msg.sender, pending);
            }
        }
        if (msg.value > 0) {
            payable(devaddr).transfer(msg.value / 100);
            user.amount = user.amount.add(msg.value.sub(msg.value / 100));
        }
        user.rewardDebt = user.amount.mul(pool.accTHENODEPerShare).div(1e12);

        THENODE.mint(msg.sender, _amount);
        emit Deposit(msg.sender, 0, _amount);
    }

    // Withdraw THENODE tokens from STAKING.
    function leaveStaking(uint256 _amount) public {
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[0][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(0);
        uint256 pending = user.amount.mul(pool.accTHENODEPerShare).div(1e12).sub(user.rewardDebt);
        if(pending > 0) {
            safeTHENODETransfer(msg.sender, pending);
        }
        if(_amount > 0) {
            user.amount = user.amount.sub(_amount);
            payable(devaddr).transfer(_amount / 100);
            payable(msg.sender).transfer(_amount.sub(_amount / 100));
        }
        user.rewardDebt = user.amount.mul(pool.accTHENODEPerShare).div(1e12);

        THENODE.burn(_amount);
        emit Withdraw(msg.sender, 0, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public {
        UserInfo storage user = userInfo[_pid][msg.sender];
        payable(msg.sender).transfer(user.amount);
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
    }

    // Safe THENODE transfer function, just in case if rounding error causes pool to not have enough THENODEs.
    function safeTHENODETransfer(address _to, uint256 _amount) internal {
        uint256 THENODEBal = THENODE.balanceOf(address(this));
        if (_amount > THENODEBal) {
            THENODE.transfer(_to, THENODEBal);
        } else {
            THENODE.transfer(_to, _amount);
        }
    }
}