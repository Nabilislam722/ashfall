// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title Ashfall saves
/// @notice One save slot per wallet for the game's checkpoints.
///
/// Deliberately minimal so there is nothing to attack:
///  - only a wallet itself can write or wipe its own slot (msg.sender), nobody else, not even
///    the deployer: there is no owner, no pause, no upgrade and no way to edit someone's save;
///  - it never holds tokens or ETH;
///  - saves are size-capped, and each one names the run it belongs to, so a save sent before
///    "New Game" can never land in the new run;
///  - the chain stamps when each run started and when it was last saved. The game server reads
///    these times to rate-limit gold exchanges; players cannot backdate them.
///
/// The save itself is opaque bytes (the game writes compact JSON with a format version inside),
/// so the game can change what it stores without a new contract.
contract AshfallSaves {
    uint256 public constant MAX_SAVE_BYTES = 4096;

    struct Slot {
        uint64 runId; // 0 until the wallet's first save or New Game, then 1, 2, ...
        uint64 runStartedAt; // block time of the current run's New Game (or first save)
        uint64 savedAt; // block time of the latest save in this run, 0 if none yet
        uint64 saveCount; // saves in this run
        bytes data;
    }

    mapping(address player => Slot) private _slots;

    event RunStarted(address indexed player, uint64 indexed runId, uint64 startedAt);
    event Saved(address indexed player, uint64 indexed runId, uint64 saveCount, bytes32 dataHash);

    error EmptySave();
    error SaveTooLarge(uint256 size, uint256 maxSize);
    error WrongRun(uint64 expected, uint64 current);

    /// @notice Store the caller's game.
    /// @param data The encoded game state (1 to MAX_SAVE_BYTES bytes).
    /// @param runId The run this save belongs to, as last read from getSave (0 if the wallet has
    /// never saved). Fails if a New Game happened since, so stale saves can't overwrite it.
    function save(bytes calldata data, uint64 runId) external {
        if (data.length == 0) revert EmptySave();
        if (data.length > MAX_SAVE_BYTES) revert SaveTooLarge(data.length, MAX_SAVE_BYTES);

        Slot storage slot = _slots[msg.sender];
        if (slot.runId == 0 && runId == 0) {
            _startRun(slot);
        } else if (runId != slot.runId) {
            revert WrongRun(runId, slot.runId);
        }

        slot.data = data;
        slot.savedAt = uint64(block.timestamp);
        slot.saveCount += 1;
        emit Saved(msg.sender, slot.runId, slot.saveCount, keccak256(data));
    }

    /// @notice Wipe the caller's save and start a new run.
    /// @return runId The new run's id.
    function newGame() external returns (uint64 runId) {
        Slot storage slot = _slots[msg.sender];
        delete slot.data;
        slot.savedAt = 0;
        slot.saveCount = 0;
        runId = _startRun(slot);
    }

    /// @notice A wallet's save slot. `data` is empty when there is nothing to load.
    function getSave(address player)
        external
        view
        returns (uint64 runId, uint64 runStartedAt, uint64 savedAt, uint64 saveCount, bytes memory data)
    {
        Slot storage slot = _slots[player];
        return (slot.runId, slot.runStartedAt, slot.savedAt, slot.saveCount, slot.data);
    }

    function hasSave(address player) external view returns (bool) {
        return _slots[player].data.length > 0;
    }

    function _startRun(Slot storage slot) private returns (uint64 runId) {
        runId = slot.runId + 1;
        slot.runId = runId;
        slot.runStartedAt = uint64(block.timestamp);
        emit RunStarted(msg.sender, runId, uint64(block.timestamp));
    }
}
