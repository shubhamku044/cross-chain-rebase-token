// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/*
 * @title RebaseToken
 * @author Shubham Kumar
 * @notice This is a cross-chain rebase token that incentivises users to deposit into a vault and gain interest in rewards.
 * @notice The interest rate in the smart contract can only decrease
 * @notice Each will user will have their own interest rate that is the global interest rate at the time of depositing.
 */
contract RebaseToken is ERC20 {
    error RebaseToken__InterestRateCanDecreaseOnly(
        uint256 oldInterestRate,
        uint256 newInterestRate
    );

    uint256 private constant PRECISION_FACTOR = 1e18;
    uint256 private s_interestRate = 5e10;
    mapping(address => uint256) private s_userInterestRate;
    mapping(address => uint256) private s_userLastUpdatedTimestamp;

    event InterestRateSet(uint256 interestRate);

    constructor() ERC20("Rebase Token", "RBT") {}

    function setInterestRate(uint256 _interestRate) external {
        if (_interestRate >= s_interestRate) {
            revert RebaseToken__InterestRateCanDecreaseOnly(
                s_interestRate,
                _interestRate
            );
        }
        s_interestRate = _interestRate;
        emit InterestRateSet(_interestRate);
    }

    function mint(address _to, uint256 _amount) external {
        _mintAccruedInterest(_to);
        s_userInterestRate[_to] = s_interestRate;
        _mint(_to, _amount);
    }

    function burn(address _from, uint256 _amount) external {
        if (_amount == type(uint256).max) {
            _amount = balanceOf(_from);
        }
        _mintAccruedInterest(_from);
        _burn(_from, _amount);
    }

    function _calculateUserAccumulatedInterestSinceLastUpdate(
        address _user
    ) internal view returns (uint256 linearInterest) {
        uint256 timeElapsed = block.timestamp -
            s_userLastUpdatedTimestamp[_user];

        linearInterest =
            PRECISION_FACTOR +
            (timeElapsed * s_userInterestRate[_user]);
    }

    function balanceOf(
        address _account
    ) public view override returns (uint256) {
        uint256 balance = ERC20.balanceOf(_account);
        uint256 interest = (balance * s_userInterestRate[_account]) / 1e18;
        return
            (super.balanceOf(_account) *
                _calculateUserAccumulatedInterestSinceLastUpdate(_account)) /
            PRECISION_FACTOR;
    }

    function _mintAccruedInterest(address _user) internal {
        uint256 previousPrincipalBalance = super.balanceOf(_user);
        uint256 currentBalance = balanceOf(_user);

        uint256 balanceIncrease = currentBalance - previousPrincipalBalance;

        s_userLastUpdatedTimestamp[_user] = block.timestamp;
        _mint(_user, balanceIncrease);
    }

    function getUserInterestRate(
        address _user
    ) external view returns (uint256) {
        return s_userInterestRate[_user];
    }
}
