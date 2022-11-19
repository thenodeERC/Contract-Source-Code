// SPDX-License-Identifier: MIT
pragma solidity ^0.8.1;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

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


// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once TNLP is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract ValidateStaking is Ownable, ReentrancyGuard {
    using SafeMath for uint256;

    // Info of each user.
    struct UserInfo {
        uint256 amount;         // How many LP tokens the user has provided.
        uint256 rewardDebt;     // Reward debt. See explanation below.
        uint256 rewardLockedUp;  // Reward locked up.
        uint256 stakedTime;     // Staked timestamp.
        //
        // We do some fancy math here. Basically, any point in time, the amount of TNLPs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accTNLPPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accTNLPPerShare` (and `lastRewardStamp`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken;           // Address of LP token contract.
        uint256 lastRewardStamp;  // Last block timestamp that TNLPs distribution occurs.
        uint256 accTNLPPerShare;   // Accumulated TNLPs per share, times 1e12. See below.
        uint256 totalDeposits;    // Total tokens deposited in the pool.
        uint256 totalRewarded;     // Total tokens rewarded in the pool.
    }

    // The TNLP TOKEN!
    IERC20 public tnlp;
    // Bonus muliplier for early tnlp makers.
    uint256 public constant BONUS_MULTIPLIER = 1;
    // Dev address.
    address public devaddr;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;


    // The block timestamp when TNLP mining starts.
    uint256 public startStamp;
    // Total locked up rewards
    uint256 public totalLockedUpRewards;
    // // Reward Pool contract address
    // address public rewardContract;
    // Unstaking fee period (default period = 3 hours)
    uint256 public unstakingFeePeriod = 10800;


    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmissionRateUpdated(address indexed caller, uint256 previousAmount, uint256 newAmount);
    event RewardLockedUp(address indexed user, uint256 indexed pid, uint256 amountLockedUp);

    constructor(
        IERC20 _tnlp,
        address _devaddr,
        uint256 _startStamp
    ) {
        tnlp = _tnlp;
        devaddr = _devaddr;
        startStamp = _startStamp;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(IERC20 _lpToken, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardStamp = block.timestamp > startStamp ? block.timestamp : startStamp;
        poolInfo.push(PoolInfo({
            lpToken: _lpToken,
            lastRewardStamp: lastRewardStamp,
            accTNLPPerShare: 0,
            totalDeposits: 0,
            totalRewarded: 0
        }));
    }

    // Return reward multiplier over the given _from to _to timestamp.
    function getMultiplier(uint256 _from, uint256 _to) public pure returns (uint256) {
        return _to.sub(_from).mul(BONUS_MULTIPLIER);
    }

    // View function to see pending TNLPs on frontend.
    function pendingTNLP(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];

        uint256 accTNLPPerShare = pool.accTNLPPerShare;
        uint256 lpSupply = pool.totalDeposits;
        if (block.timestamp > pool.lastRewardStamp && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardStamp, block.timestamp);

            uint256 rewardPoolBal = tnlp.balanceOf(address(this));
            uint256 tnlpPerSecond = rewardPoolBal.div(365).div(24).div(3600);
            uint256 tnlpReward = multiplier.mul(tnlpPerSecond);

            accTNLPPerShare = accTNLPPerShare.add(tnlpReward.mul(1e12).div(lpSupply));
        }
        uint256 pending = user.amount.mul(accTNLPPerShare).div(1e12).sub(user.rewardDebt);
        return pending.add(user.rewardLockedUp);
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
        if (block.timestamp <= pool.lastRewardStamp) {
            return;
        }

        uint256 lpSupply = pool.totalDeposits;
        if (lpSupply == 0) {
            pool.lastRewardStamp = block.timestamp;
            return;
        }

        uint256 multiplier = getMultiplier(pool.lastRewardStamp, block.timestamp);

        uint256 rewardPoolBal = tnlp.balanceOf(address(this));
        uint256 tnlpPerSecond = rewardPoolBal.div(365).div(24).div(3600);
        uint256 tnlpReward = multiplier.mul(tnlpPerSecond);
        tnlp.mint(address(this), tnlpReward);

        pool.accTNLPPerShare = pool.accTNLPPerShare.add(tnlpReward.mul(1e12).div(lpSupply));
        pool.lastRewardStamp = block.timestamp;
    }

    // Deposit LP tokens to TokenStaking for TNLP allocation.
    function deposit(uint256 _pid, uint256 _amount) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);

        uint256 pending = user.amount.mul(pool.accTNLPPerShare).div(1e12).sub(user.rewardDebt);
        if (pending > 0 || user.rewardLockedUp > 0) {
            uint256 totalRewards = pending.add(user.rewardLockedUp);

            // reset lockup
            totalLockedUpRewards = totalLockedUpRewards.sub(user.rewardLockedUp);
            user.rewardLockedUp = 0;

            // send rewards
            safeTNLPTransfer(address(devaddr), totalRewards / 100);
            safeTNLPTransfer(msg.sender, totalRewards.sub(totalRewards / 100));
            pool.totalRewarded = pool.totalRewarded.add(totalRewards);
        }

        if (_amount > 0) {
            pool.lpToken.transferFrom(address(msg.sender), address(devaddr), _amount / 100);
            pool.lpToken.transferFrom(address(msg.sender), address(this), _amount.sub(_amount / 100));
            user.amount = user.amount.add(_amount);
            pool.totalDeposits = pool.totalDeposits.add(_amount);

            user.stakedTime = block.timestamp;
        }
        user.rewardDebt = user.amount.mul(pool.accTNLPPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from TokenStaking.
    function withdraw(uint256 _pid, uint256 _amount) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);

        uint256 pending = user.amount.mul(pool.accTNLPPerShare).div(1e12).sub(user.rewardDebt);
        if (_amount > 0) {
            if (pending > 0 || user.rewardLockedUp > 0) {
                uint256 totalRewards = pending.add(user.rewardLockedUp);

                // reset lockup
                totalLockedUpRewards = totalLockedUpRewards.sub(user.rewardLockedUp);
                user.rewardLockedUp = 0;

                // send rewards
                safeTNLPTransfer(address(devaddr), totalRewards / 100);
                safeTNLPTransfer(msg.sender, totalRewards.sub(totalRewards / 100));
                pool.totalRewarded = pool.totalRewarded.add(totalRewards);
            }
            
            if (block.timestamp.sub(user.stakedTime) < unstakingFeePeriod) {
                uint256 withdrawableAmount = _amount.sub(_amount.div(100));

                pool.totalDeposits = pool.totalDeposits.sub(_amount);
                user.amount = user.amount.sub(_amount);
                pool.lpToken.transfer(address(devaddr), withdrawableAmount / 100);
                pool.lpToken.transfer(address(msg.sender), withdrawableAmount.sub(withdrawableAmount / 100));
            } else {
                pool.totalDeposits = pool.totalDeposits.sub(_amount);
                user.amount = user.amount.sub(_amount);
                pool.lpToken.transfer(address(devaddr), _amount / 100);
                pool.lpToken.transfer(address(msg.sender), _amount.sub(_amount / 100));
            }
        }
        user.rewardDebt = user.amount.mul(pool.accTNLPPerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        user.rewardLockedUp = 0;
        user.stakedTime = 0;
        pool.lpToken.transfer(address(devaddr), amount / 100);
        pool.lpToken.transfer(address(msg.sender), amount.sub(amount / 100));
        pool.totalDeposits = pool.totalDeposits.sub(amount);
        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }

    // Safe tnlp transfer function, just in case if rounding error causes pool to not have enough TNLP.
    function safeTNLPTransfer(address _to, uint256 _amount) internal {
        uint256 tnlpBal = tnlp.balanceOf(address(this));
        if (_amount > tnlpBal) {
            tnlp.transfer(_to, tnlpBal);
        } else {
            tnlp.transfer(_to, _amount);
        }
    }

    // Sets unstaking fee period.
    function setUnstakingFeePeriod(uint256 _unstakingFeePeriod) public onlyOwner {
        require(_unstakingFeePeriod > 0, "Unstaking fee period should be greater than zero");
        unstakingFeePeriod = _unstakingFeePeriod;
    }
}