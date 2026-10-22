// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Ownable, Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title Ashfall rewards (v2)
/// @notice Pays game rewards in any allowed ERC-20 token (HEMI first) against vouchers signed
/// by the game server.
///
/// A voucher states the player's *cumulative* allowance for one token. The contract remembers
/// how much of each token each player has already claimed and only pays the difference, so an
/// old voucher, a duplicate voucher, or two vouchers for the same total can never pay out twice.
///
/// One contract can hand out several tokens: the owner allows a token, sends the contract a
/// budget of it, and the server signs vouchers for it. The contract only ever spends what it
/// holds, so the budget is the most it can ever lose. The signer key never holds funds.
contract AshfallRewards is EIP712, Ownable2Step, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant CLAIM_TYPEHASH =
        keccak256("Claim(address recipient,address token,uint256 cumulativeAmount,uint256 deadline)");

    address public signer;
    mapping(IERC20 token => bool) public tokenAllowed;
    mapping(IERC20 token => mapping(address recipient => uint256 amount)) public claimed;
    mapping(IERC20 token => uint256 amount) public totalClaimed;

    event Claimed(address indexed recipient, IERC20 indexed token, uint256 amount, uint256 cumulativeAmount);
    event SignerChanged(address indexed signer);
    event TokenAllowed(IERC20 indexed token, bool allowed);
    event Withdrawn(IERC20 indexed token, address indexed to, uint256 amount);
    event EtherWithdrawn(address indexed to, uint256 amount);

    error ZeroAddress();
    error VoucherExpired();
    error InvalidSignature();
    error NothingToClaim();
    error TokenNotAllowed(IERC20 token);
    error EtherTransferFailed();
    error RenounceDisabled();

    constructor(address signer_, address owner_, IERC20[] memory tokens_)
        EIP712("AshfallRewards", "2")
        Ownable(owner_)
    {
        if (signer_ == address(0)) revert ZeroAddress();
        signer = signer_;
        emit SignerChanged(signer_);
        for (uint256 i = 0; i < tokens_.length; i++) {
            _setTokenAllowed(tokens_[i], true);
        }
    }

    // ------------------------------------------------------------------ players

    /// @notice Claim everything the server has credited to the caller so far in `token`.
    /// @param token The reward token the voucher is for.
    /// @param cumulativeAmount Total amount (in token units) ever credited to the caller in `token`.
    /// @param deadline Unix time after which the voucher is no longer accepted.
    /// @param signature Server's EIP-712 signature over (caller, token, cumulativeAmount, deadline).
    /// @return amount What this call paid out.
    function claim(IERC20 token, uint256 cumulativeAmount, uint256 deadline, bytes calldata signature)
        external
        whenNotPaused
        nonReentrant
        returns (uint256 amount)
    {
        if (!tokenAllowed[token]) revert TokenNotAllowed(token);
        if (block.timestamp > deadline) revert VoucherExpired();

        bytes32 digest = _hashTypedDataV4(
            keccak256(abi.encode(CLAIM_TYPEHASH, msg.sender, address(token), cumulativeAmount, deadline))
        );
        if (ECDSA.recover(digest, signature) != signer) revert InvalidSignature();

        uint256 alreadyClaimed = claimed[token][msg.sender];
        if (cumulativeAmount <= alreadyClaimed) revert NothingToClaim();

        amount = cumulativeAmount - alreadyClaimed;
        claimed[token][msg.sender] = cumulativeAmount;
        totalClaimed[token] += amount;
        token.safeTransfer(msg.sender, amount);

        emit Claimed(msg.sender, token, amount, cumulativeAmount);
    }

    /// @notice Tokens of `token` the contract still holds for players.
    function budget(IERC20 token) external view returns (uint256) {
        return token.balanceOf(address(this));
    }

    /// @notice Domain separator used by the server when signing vouchers.
    function domainSeparator() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    // ------------------------------------------------------------------ owner

    /// @notice Rotate the server signing key (e.g. if the Worker secret leaks). Outstanding
    /// vouchers signed by the old key stop working.
    function setSigner(address newSigner) external onlyOwner {
        if (newSigner == address(0)) revert ZeroAddress();
        signer = newSigner;
        emit SignerChanged(newSigner);
    }

    /// @notice Allow (or stop) payouts in `token`. Stopping a token does not touch its budget;
    /// withdraw it separately if you want it back.
    function setTokenAllowed(IERC20 token, bool allowed) external onlyOwner {
        _setTokenAllowed(token, allowed);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice Take part of a token's budget back out of the contract.
    function withdraw(IERC20 token, address to, uint256 amount) external onlyOwner nonReentrant {
        if (to == address(0)) revert ZeroAddress();
        token.safeTransfer(to, amount);
        emit Withdrawn(token, to, amount);
    }

    /// @notice Take a token's whole remaining budget back out of the contract.
    /// @return amount What was withdrawn.
    function withdrawAll(IERC20 token, address to) external onlyOwner nonReentrant returns (uint256 amount) {
        amount = _withdrawAll(token, to);
    }

    /// @notice Empty the contract of several tokens in one transaction.
    function withdrawAllTokens(IERC20[] calldata tokens, address to) external onlyOwner nonReentrant {
        for (uint256 i = 0; i < tokens.length; i++) {
            _withdrawAll(tokens[i], to);
        }
    }

    /// @notice Recover ETH that was forced into the contract (it never needs any).
    function withdrawEther(address payable to) external onlyOwner nonReentrant {
        if (to == address(0)) revert ZeroAddress();
        uint256 amount = address(this).balance;
        (bool ok,) = to.call{value: amount}("");
        if (!ok) revert EtherTransferFailed();
        emit EtherWithdrawn(to, amount);
    }

    /// @notice Disabled: an owner-less contract could never return its budget or rotate a
    /// leaked signer. Hand ownership over with transferOwnership + acceptOwnership instead.
    function renounceOwnership() public view override onlyOwner {
        revert RenounceDisabled();
    }

    // ------------------------------------------------------------------ internal

    function _setTokenAllowed(IERC20 token, bool allowed) internal {
        if (address(token) == address(0)) revert ZeroAddress();
        tokenAllowed[token] = allowed;
        emit TokenAllowed(token, allowed);
    }

    function _withdrawAll(IERC20 token, address to) internal returns (uint256 amount) {
        if (to == address(0)) revert ZeroAddress();
        amount = token.balanceOf(address(this));
        if (amount > 0) token.safeTransfer(to, amount);
        emit Withdrawn(token, to, amount);
    }
}
