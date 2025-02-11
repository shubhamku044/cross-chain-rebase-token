// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Vault} from "../src/Vault.sol";

import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";

contract RebaseTokenTest is Test {
    RebaseToken private rebaseToken;
    Vault private vault;

    address public owner = makeAddr("owner");
    address public user = makeAddr("user");

    function setUp() public {
        vm.deal(owner, 100 ether);
        vm.startPrank(owner);
        rebaseToken = new RebaseToken();
        vault = new Vault(IRebaseToken(address(rebaseToken)));
        rebaseToken.grantMintAndBurnRole(address(vault));
        vm.stopPrank();
    }

    function addRewardsToVault(uint256 rewardAmount) public {
        (bool success, ) = payable(address(vault)).call{value: rewardAmount}(
            ""
        );
    }

    function testDepositLinear(uint96 amount) public {
        // Deposit funds
        vm.assume(amount >= 1e5 && amount <= 100 ether);

        vm.startPrank(user);
        vm.deal(user, amount);

        // Log pre-deposit balances
        console.log("Testing with amount:", amount);
        console.log("User ETH balance:", address(user).balance);
        console.log("Vault ETH balance:", address(vault).balance);

        // 1. deposit
        vault.deposit{value: amount}();
        // 2. check our rebase token balance
        uint256 startBalance = rebaseToken.balanceOf(user);
        console.log("block.timestamp", block.timestamp);
        console.log("startBalance", startBalance);
        assertEq(
            startBalance,
            amount,
            "Initial balance should be equal to the amount deposited"
        );
        // 3. warp the time and check the balance again
        vm.warp(block.timestamp + 1 hours);
        console.log("block.timestamp", block.timestamp);
        uint256 middleBalance = rebaseToken.balanceOf(user);
        console.log("middleBalance", middleBalance);
        assertGt(
            middleBalance,
            startBalance,
            "Balance should increase after 1 hour"
        );
        // 4. warp the time again by the same amount and check the balance again
        vm.warp(block.timestamp + 1 hours);
        uint256 endBalance = rebaseToken.balanceOf(user);
        console.log("block.timestamp", block.timestamp);
        console.log("endBalance", endBalance);
        assertGt(
            endBalance,
            middleBalance,
            "Balance should increase after 1 hour"
        );

        uint256 firstIncrease = middleBalance - startBalance;
        uint256 secondIncrease = endBalance - middleBalance;

        assertApproxEqAbs(
            firstIncrease,
            secondIncrease,
            0.01e18,
            "Increase should be linear"
        );

        vm.stopPrank();
    }

    function testRedeemStraightAway(uint256 amount) public {
        amount = bound(amount, 1e5, type(uint96).max);

        vm.startPrank(user);
        vm.deal(user, amount);
        vault.deposit{value: amount}();

        assertEq(
            rebaseToken.balanceOf(user),
            amount,
            "User should have deposited amount"
        );

        vault.redeem(type(uint256).max);
        assertEq(rebaseToken.balanceOf(user), 0, "User should have 0 balance");
        assertEq(address(user).balance, amount, "User should have 1 ETH");
        vm.stopPrank();
    }

    function testRedeemAfterTimePassed(
        uint256 depositAmount,
        uint256 time
    ) public {
        time = bound(time, 1000, type(uint96).max);
        depositAmount = bound(depositAmount, 1e5, type(uint96).max);

        vm.startPrank(user);
        vm.deal(user, depositAmount);

        vm.warp(block.timestamp + time);
        uint256 balanceAfterSometime = rebaseToken.balanceOf(user);
        vm.stopPrank(); // Stop user prank here

        vm.deal(owner, balanceAfterSometime);
        vm.prank(owner); // Correctly set owner prank for next call
        addRewardsToVault(depositAmount - balanceAfterSometime);

        vm.prank(user); // Set user prank for redeem call
        vault.redeem(type(uint256).max);

        uint256 ethBalance = address(user).balance;
        assertEq(ethBalance, depositAmount, "User should have 1 ETH");
        assertGt(
            ethBalance,
            balanceAfterSometime,
            "User should have more than deposited"
        );
    }

    function testTransfer(uint256 amount, uint256 amountToSend) public {
        amount = bound(amount, 1e5 + 1e5, type(uint96).max);
        amountToSend = bound(amountToSend, 1e5, amount - 1e5);

        vm.deal(user, amount);
        vm.prank(user);
        vault.deposit{value: amount}();

        address user2 = makeAddr("user2");
        uint256 userBalance = rebaseToken.balanceOf(user);
        uint256 user2Balance = rebaseToken.balanceOf(user2);

        assertEq(userBalance, amount, "User should have deposited amount");
        assertEq(user2Balance, 0, "User2 should have 0 balance");

        // Switch to owner account to set interest rate
        vm.prank(owner);
        rebaseToken.setInterestRate(4e10);

        vm.prank(user);
        rebaseToken.transfer(user2, amountToSend);

        uint256 userBalanceAfterTransfer = rebaseToken.balanceOf(user);
        uint256 user2BalanceAfterTransfer = rebaseToken.balanceOf(user2);

        assertEq(
            userBalanceAfterTransfer,
            amount - amountToSend,
            "User should have deposited amount - amountToSend"
        );
        assertEq(
            user2BalanceAfterTransfer,
            amountToSend,
            "User2 should have amountToSend"
        );

        assertEq(
            rebaseToken.getUserInterestRate(user),
            5e10,
            "Interest rate should be 4e10"
        );
        assertEq(
            rebaseToken.getUserInterestRate(user2),
            5e10,
            "Interest rate should be 4e10"
        );
    }

    function testCannotSetInterestRate(uint256 newinterestRate) public {
        vm.prank(user);
        vm.expectRevert();
        rebaseToken.setInterestRate(newinterestRate);
    }

    function testCannotMintAndBurn() public {
        vm.prank(user);
        vm.expectRevert();
        rebaseToken.mint(user, 100, 5e10);
        vm.expectRevert();
        rebaseToken.burn(user, 100);
    }

    function testGetPrincipleAmount(uint256 amount) public {
        amount = bound(amount, 1e5, type(uint96).max);
        vm.deal(user, amount);
        vm.prank(user);
        vault.deposit{value: amount}();
        assertEq(
            rebaseToken.principalBalanceOf(user),
            amount,
            "Principle amount should be equal to the deposited amount"
        );

        vm.warp(block.timestamp + 1 hours);
        assertEq(
            rebaseToken.principalBalanceOf(user),
            amount,
            "Principle amount should be equal to the deposited amount"
        );
    }

    receive() external payable {}
}
