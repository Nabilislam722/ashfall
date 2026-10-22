// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AshfallRewards} from "../src/AshfallRewards.sol";
import {TestHemiToken} from "../src/TestHemiToken.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract AshfallRewardsTest is Test {
    AshfallRewards rewards;
    TestHemiToken hemi;
    TestHemiToken other; // a second reward token, e.g. a partner token later on

    uint256 signerKey = 0xA11CE;
    address signer;
    address owner = makeAddr("owner");
    address player = makeAddr("player");
    address cheater = makeAddr("cheater");

    uint256 constant BUDGET = 1_000 ether;

    function setUp() public {
        signer = vm.addr(signerKey);
        hemi = new TestHemiToken(owner);
        other = new TestHemiToken(owner);
        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = hemi;
        rewards = new AshfallRewards(signer, owner, tokens);
        vm.startPrank(owner);
        hemi.mint(address(rewards), BUDGET);
        other.mint(address(rewards), BUDGET);
        vm.stopPrank();
    }

    function _voucher(uint256 key, address recipient, IERC20 token, uint256 cumulative, uint256 deadline)
        internal
        view
        returns (bytes memory)
    {
        bytes32 structHash =
            keccak256(abi.encode(rewards.CLAIM_TYPEHASH(), recipient, address(token), cumulative, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", rewards.domainSeparator(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, digest);
        return abi.encodePacked(r, s, v);
    }

    function _deadline() internal view returns (uint256) {
        return block.timestamp + 1 hours;
    }

    // ---------------------------------------------------------------- claiming

    function test_claimPaysTheVoucherAmount() public {
        uint256 deadline = _deadline();
        bytes memory sig = _voucher(signerKey, player, hemi, 5 ether, deadline);

        vm.prank(player);
        uint256 paid = rewards.claim(hemi, 5 ether, deadline, sig);

        assertEq(paid, 5 ether);
        assertEq(hemi.balanceOf(player), 5 ether);
        assertEq(rewards.claimed(hemi, player), 5 ether);
        assertEq(rewards.totalClaimed(hemi), 5 ether);
        assertEq(rewards.budget(hemi), BUDGET - 5 ether);
    }

    function test_cumulativeVoucherOnlyPaysTheDifference() public {
        uint256 deadline = _deadline();
        vm.startPrank(player);
        rewards.claim(hemi, 5 ether, deadline, _voucher(signerKey, player, hemi, 5 ether, deadline));
        rewards.claim(hemi, 8 ether, deadline, _voucher(signerKey, player, hemi, 8 ether, deadline));
        vm.stopPrank();

        assertEq(hemi.balanceOf(player), 8 ether);
        assertEq(rewards.claimed(hemi, player), 8 ether);
    }

    function test_replayingAVoucherPaysNothing() public {
        uint256 deadline = _deadline();
        bytes memory sig = _voucher(signerKey, player, hemi, 5 ether, deadline);
        vm.startPrank(player);
        rewards.claim(hemi, 5 ether, deadline, sig);
        vm.expectRevert(AshfallRewards.NothingToClaim.selector);
        rewards.claim(hemi, 5 ether, deadline, sig);
        vm.stopPrank();
    }

    function test_olderSmallerVoucherCannotBeUsedAfterABiggerOne() public {
        uint256 deadline = _deadline();
        bytes memory small = _voucher(signerKey, player, hemi, 3 ether, deadline);
        vm.startPrank(player);
        rewards.claim(hemi, 8 ether, deadline, _voucher(signerKey, player, hemi, 8 ether, deadline));
        vm.expectRevert(AshfallRewards.NothingToClaim.selector);
        rewards.claim(hemi, 3 ether, deadline, small);
        vm.stopPrank();
    }

    function test_someoneElseCannotUseMyVoucher() public {
        uint256 deadline = _deadline();
        bytes memory sig = _voucher(signerKey, player, hemi, 5 ether, deadline);
        vm.prank(cheater);
        vm.expectRevert(AshfallRewards.InvalidSignature.selector);
        rewards.claim(hemi, 5 ether, deadline, sig);
    }

    function test_voucherSignedByTheWrongKeyIsRejected() public {
        uint256 deadline = _deadline();
        bytes memory sig = _voucher(0xBAD, player, hemi, 5 ether, deadline);
        vm.prank(player);
        vm.expectRevert(AshfallRewards.InvalidSignature.selector);
        rewards.claim(hemi, 5 ether, deadline, sig);
    }

    function test_inflatingTheAmountBreaksTheSignature() public {
        uint256 deadline = _deadline();
        bytes memory sig = _voucher(signerKey, player, hemi, 5 ether, deadline);
        vm.prank(player);
        vm.expectRevert(AshfallRewards.InvalidSignature.selector);
        rewards.claim(hemi, 500 ether, deadline, sig);
    }

    function test_expiredVoucherIsRejected() public {
        uint256 deadline = _deadline();
        bytes memory sig = _voucher(signerKey, player, hemi, 5 ether, deadline);
        vm.warp(deadline + 1);
        vm.prank(player);
        vm.expectRevert(AshfallRewards.VoucherExpired.selector);
        rewards.claim(hemi, 5 ether, deadline, sig);
    }

    function test_claimsFailWhenTheBudgetRunsOut() public {
        uint256 deadline = _deadline();
        bytes memory sig = _voucher(signerKey, player, hemi, BUDGET + 1, deadline);
        vm.prank(player);
        vm.expectRevert();
        rewards.claim(hemi, BUDGET + 1, deadline, sig);
        assertEq(rewards.claimed(hemi, player), 0);
    }

    // ---------------------------------------------------------------- several tokens

    function test_tokensMustBeAllowedBeforeTheyPay() public {
        uint256 deadline = _deadline();
        bytes memory sig = _voucher(signerKey, player, other, 5 ether, deadline);
        vm.prank(player);
        vm.expectRevert(abi.encodeWithSelector(AshfallRewards.TokenNotAllowed.selector, other));
        rewards.claim(other, 5 ether, deadline, sig);

        vm.prank(owner);
        rewards.setTokenAllowed(other, true);
        vm.prank(player);
        rewards.claim(other, 5 ether, deadline, sig);
        assertEq(other.balanceOf(player), 5 ether);
    }

    function test_eachTokenKeepsItsOwnTally() public {
        vm.prank(owner);
        rewards.setTokenAllowed(other, true);
        uint256 deadline = _deadline();
        vm.startPrank(player);
        rewards.claim(hemi, 5 ether, deadline, _voucher(signerKey, player, hemi, 5 ether, deadline));
        rewards.claim(other, 2 ether, deadline, _voucher(signerKey, player, other, 2 ether, deadline));
        vm.stopPrank();
        assertEq(rewards.claimed(hemi, player), 5 ether);
        assertEq(rewards.claimed(other, player), 2 ether);
        assertEq(hemi.balanceOf(player), 5 ether);
        assertEq(other.balanceOf(player), 2 ether);
    }

    function test_aVoucherForOneTokenCannotBeSpentInAnother() public {
        vm.prank(owner);
        rewards.setTokenAllowed(other, true);
        uint256 deadline = _deadline();
        bytes memory hemiSig = _voucher(signerKey, player, hemi, 5 ether, deadline);
        vm.prank(player);
        vm.expectRevert(AshfallRewards.InvalidSignature.selector);
        rewards.claim(other, 5 ether, deadline, hemiSig);
    }

    function test_stoppingATokenBlocksItsClaims() public {
        uint256 deadline = _deadline();
        bytes memory sig = _voucher(signerKey, player, hemi, 5 ether, deadline);
        vm.prank(owner);
        rewards.setTokenAllowed(hemi, false);
        vm.prank(player);
        vm.expectRevert(abi.encodeWithSelector(AshfallRewards.TokenNotAllowed.selector, hemi));
        rewards.claim(hemi, 5 ether, deadline, sig);
    }

    // ---------------------------------------------------------------- owner

    function test_pauseStopsClaims() public {
        uint256 deadline = _deadline();
        bytes memory sig = _voucher(signerKey, player, hemi, 5 ether, deadline);
        vm.prank(owner);
        rewards.pause();
        vm.prank(player);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        rewards.claim(hemi, 5 ether, deadline, sig);
    }

    function test_rotatingTheSignerInvalidatesOldVouchers() public {
        uint256 deadline = _deadline();
        bytes memory oldSig = _voucher(signerKey, player, hemi, 5 ether, deadline);
        uint256 newKey = 0xB0B;
        vm.prank(owner);
        rewards.setSigner(vm.addr(newKey));

        vm.prank(player);
        vm.expectRevert(AshfallRewards.InvalidSignature.selector);
        rewards.claim(hemi, 5 ether, deadline, oldSig);

        bytes memory newSig = _voucher(newKey, player, hemi, 5 ether, deadline);
        vm.prank(player);
        rewards.claim(hemi, 5 ether, deadline, newSig);
        assertEq(hemi.balanceOf(player), 5 ether);
    }

    function test_onlyOwnerCanManage() public {
        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = hemi;
        vm.startPrank(cheater);
        bytes memory notOwner = abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, cheater);
        vm.expectRevert(notOwner);
        rewards.withdraw(hemi, cheater, 1 ether);
        vm.expectRevert(notOwner);
        rewards.withdrawAll(hemi, cheater);
        vm.expectRevert(notOwner);
        rewards.withdrawAllTokens(tokens, cheater);
        vm.expectRevert(notOwner);
        rewards.withdrawEther(payable(cheater));
        vm.expectRevert(notOwner);
        rewards.setSigner(cheater);
        vm.expectRevert(notOwner);
        rewards.setTokenAllowed(other, true);
        vm.expectRevert(notOwner);
        rewards.pause();
        vm.stopPrank();
    }

    function test_ownerCanWithdrawPartOfTheBudget() public {
        vm.prank(owner);
        rewards.withdraw(hemi, owner, 100 ether);
        assertEq(hemi.balanceOf(owner), 100 ether);
        assertEq(rewards.budget(hemi), BUDGET - 100 ether);
    }

    function test_withdrawAllEmptiesAToken() public {
        vm.prank(owner);
        uint256 amount = rewards.withdrawAll(hemi, owner);
        assertEq(amount, BUDGET);
        assertEq(hemi.balanceOf(owner), BUDGET);
        assertEq(rewards.budget(hemi), 0);
    }

    function test_withdrawAllTokensEmptiesEverything() public {
        IERC20[] memory tokens = new IERC20[](2);
        tokens[0] = hemi;
        tokens[1] = other; // not even allowed: unused budgets can always come back
        vm.prank(owner);
        rewards.withdrawAllTokens(tokens, owner);
        assertEq(hemi.balanceOf(owner), BUDGET);
        assertEq(other.balanceOf(owner), BUDGET);
        assertEq(rewards.budget(hemi), 0);
        assertEq(rewards.budget(other), 0);
    }

    function test_withdrawAllOnAnEmptyTokenIsHarmless() public {
        vm.startPrank(owner);
        rewards.withdrawAll(hemi, owner);
        assertEq(rewards.withdrawAll(hemi, owner), 0);
        vm.stopPrank();
    }

    function test_withdrawToZeroAddressIsRejected() public {
        vm.startPrank(owner);
        vm.expectRevert(AshfallRewards.ZeroAddress.selector);
        rewards.withdrawAll(hemi, address(0));
        vm.expectRevert(AshfallRewards.ZeroAddress.selector);
        rewards.withdraw(hemi, address(0), 1);
        vm.stopPrank();
    }

    function test_forcedEtherCanBeRecovered() public {
        vm.deal(address(rewards), 1 ether);
        vm.prank(owner);
        rewards.withdrawEther(payable(owner));
        assertEq(owner.balance, 1 ether);
    }

    function test_ownershipCannotBeRenounced() public {
        vm.prank(owner);
        vm.expectRevert(AshfallRewards.RenounceDisabled.selector);
        rewards.renounceOwnership();
        assertEq(rewards.owner(), owner);
    }

    function test_ownershipMovesInTwoSteps() public {
        address next = makeAddr("next");
        vm.prank(owner);
        rewards.transferOwnership(next);
        assertEq(rewards.owner(), owner);
        vm.prank(next);
        rewards.acceptOwnership();
        assertEq(rewards.owner(), next);
    }

    // ---------------------------------------------------------------- fuzz

    function testFuzz_neverPaysMoreThanTheLatestVoucher(uint96 first, uint96 second) public {
        vm.assume(first > 0 && second > first && second <= BUDGET);
        uint256 deadline = _deadline();
        vm.startPrank(player);
        rewards.claim(hemi, first, deadline, _voucher(signerKey, player, hemi, first, deadline));
        rewards.claim(hemi, second, deadline, _voucher(signerKey, player, hemi, second, deadline));
        vm.stopPrank();
        assertEq(hemi.balanceOf(player), second);
        assertEq(rewards.totalClaimed(hemi), second);
    }
}
