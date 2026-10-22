// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {AshfallSaves} from "../src/AshfallSaves.sol";

contract AshfallSavesTest is Test {
    AshfallSaves saves;
    address player = makeAddr("player");
    address other = makeAddr("other");

    bytes constant SAVE_1 = bytes('{"v":1,"map":"test","gold":10}');
    bytes constant SAVE_2 = bytes('{"v":1,"map":"village","gold":42}');

    function setUp() public {
        saves = new AshfallSaves();
        vm.warp(1_800_000_000);
    }

    function _slot(address who)
        internal
        view
        returns (uint64 runId, uint64 runStartedAt, uint64 savedAt, uint64 saveCount, bytes memory data)
    {
        return saves.getSave(who);
    }

    function test_aNewWalletHasNothingToLoad() public view {
        (uint64 runId,,,, bytes memory data) = _slot(player);
        assertEq(runId, 0);
        assertEq(data.length, 0);
        assertFalse(saves.hasSave(player));
    }

    function test_firstSaveStartsRunOne() public {
        vm.prank(player);
        saves.save(SAVE_1, 0);
        (uint64 runId, uint64 startedAt, uint64 savedAt, uint64 count, bytes memory data) = _slot(player);
        assertEq(runId, 1);
        assertEq(startedAt, block.timestamp);
        assertEq(savedAt, block.timestamp);
        assertEq(count, 1);
        assertEq(data, SAVE_1);
        assertTrue(saves.hasSave(player));
    }

    function test_laterSavesReplaceTheSlot() public {
        vm.startPrank(player);
        saves.save(SAVE_1, 0);
        vm.warp(block.timestamp + 60);
        saves.save(SAVE_2, 1);
        vm.stopPrank();
        (uint64 runId, uint64 startedAt, uint64 savedAt, uint64 count, bytes memory data) = _slot(player);
        assertEq(runId, 1);
        assertEq(startedAt, block.timestamp - 60);
        assertEq(savedAt, block.timestamp);
        assertEq(count, 2);
        assertEq(data, SAVE_2);
    }

    function test_nobodyCanWriteSomeoneElsesSave() public {
        vm.prank(player);
        saves.save(SAVE_1, 0);
        vm.prank(other);
        saves.save(SAVE_2, 0); // lands in the other wallet's own slot
        (,,,, bytes memory mine) = _slot(player);
        (,,,, bytes memory theirs) = _slot(other);
        assertEq(mine, SAVE_1);
        assertEq(theirs, SAVE_2);
    }

    function test_nobodyCanWipeSomeoneElsesSave() public {
        vm.prank(player);
        saves.save(SAVE_1, 0);
        vm.prank(other);
        saves.newGame(); // only resets the caller
        (uint64 runId,,,, bytes memory data) = _slot(player);
        assertEq(runId, 1);
        assertEq(data, SAVE_1);
    }

    function test_newGameWipesTheSaveAndStartsANewRun() public {
        vm.startPrank(player);
        saves.save(SAVE_1, 0);
        vm.warp(block.timestamp + 600);
        uint64 newRun = saves.newGame();
        vm.stopPrank();
        (uint64 runId, uint64 startedAt, uint64 savedAt, uint64 count, bytes memory data) = _slot(player);
        assertEq(newRun, 2);
        assertEq(runId, 2);
        assertEq(startedAt, block.timestamp);
        assertEq(savedAt, 0);
        assertEq(count, 0);
        assertEq(data.length, 0);
        assertFalse(saves.hasSave(player));
    }

    function test_aStaleSaveCannotLandAfterNewGame() public {
        vm.startPrank(player);
        saves.save(SAVE_1, 0);
        saves.newGame();
        vm.expectRevert(abi.encodeWithSelector(AshfallSaves.WrongRun.selector, uint64(1), uint64(2)));
        saves.save(SAVE_2, 1);
        saves.save(SAVE_2, 2);
        vm.stopPrank();
        (,,,, bytes memory data) = _slot(player);
        assertEq(data, SAVE_2);
    }

    function test_runZeroOnlyWorksForAFreshWallet() public {
        vm.startPrank(player);
        saves.save(SAVE_1, 0);
        vm.expectRevert(abi.encodeWithSelector(AshfallSaves.WrongRun.selector, uint64(0), uint64(1)));
        saves.save(SAVE_2, 0);
        vm.expectRevert(abi.encodeWithSelector(AshfallSaves.WrongRun.selector, uint64(7), uint64(1)));
        saves.save(SAVE_2, 7);
        vm.stopPrank();
    }

    function test_newGameOnAFreshWalletStartsRunOne() public {
        vm.prank(player);
        assertEq(saves.newGame(), 1);
        vm.prank(player);
        saves.save(SAVE_1, 1);
        (uint64 runId,,,, bytes memory data) = _slot(player);
        assertEq(runId, 1);
        assertEq(data, SAVE_1);
    }

    function test_emptySavesAreRejected() public {
        vm.prank(player);
        vm.expectRevert(AshfallSaves.EmptySave.selector);
        saves.save("", 0);
    }

    function test_oversizedSavesAreRejected() public {
        uint256 max = saves.MAX_SAVE_BYTES();
        bytes memory big = new bytes(max + 1);
        vm.prank(player);
        vm.expectRevert(abi.encodeWithSelector(AshfallSaves.SaveTooLarge.selector, max + 1, max));
        saves.save(big, 0);

        bytes memory fits = new bytes(max);
        fits[0] = "{";
        vm.prank(player);
        saves.save(fits, 0);
        (,,,, bytes memory data) = _slot(player);
        assertEq(data.length, max);
    }

    function test_runStartTimeCannotBeBackdated() public {
        vm.prank(player);
        saves.newGame();
        uint64 started = uint64(block.timestamp);
        vm.warp(block.timestamp + 3600);
        vm.prank(player);
        saves.save(SAVE_1, 1);
        (, uint64 runStartedAt,,,) = _slot(player);
        assertEq(runStartedAt, started, "saving must not move the run start");
    }

    function test_eventsDescribeEachSave() public {
        vm.expectEmit(true, true, false, true, address(saves));
        emit AshfallSaves.RunStarted(player, 1, uint64(block.timestamp));
        vm.expectEmit(true, true, false, true, address(saves));
        emit AshfallSaves.Saved(player, 1, 1, keccak256(SAVE_1));
        vm.prank(player);
        saves.save(SAVE_1, 0);
    }

    function testFuzz_onlyTheCallersSlotChanges(address a, address b, bytes calldata data) public {
        vm.assume(a != b && data.length > 0 && data.length <= 4096);
        vm.prank(b);
        saves.save(SAVE_1, 0);
        vm.prank(a);
        saves.save(data, 0);
        (,,,, bytes memory theirs) = _slot(b);
        (,,,, bytes memory mine) = _slot(a);
        assertEq(theirs, SAVE_1);
        assertEq(mine, data);
    }
}
