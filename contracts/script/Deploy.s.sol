// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AshfallRewards} from "../src/AshfallRewards.sol";
import {AshfallSaves} from "../src/AshfallSaves.sol";
import {TestHemiToken} from "../src/TestHemiToken.sol";

/// Deploys the rewards contract and the saves contract.
///
/// Required env:
///   REWARDS_SIGNER   address of the Worker's signing key (holds no funds)
/// Optional env:
///   REWARD_TOKEN     first token to pay out. On Hemi mainnet it defaults to HEMI and must be HEMI
///                    (more tokens can be allowed later with setTokenAllowed). Leave unset on a
///                    testnet to deploy a test token (tHEMI) and fund the contract with TEST_BUDGET
///                    (default 100000 tokens).
///   REWARDS_OWNER    owner of the rewards contract (default: the deployer)
///
/// The saves contract has no owner and no settings.
///
/// Example (Hemi mainnet, using an encrypted keystore account):
///   forge script script/Deploy.s.sol --rpc-url hemi --account deployer --broadcast
contract Deploy is Script {
    uint256 constant HEMI_MAINNET = 43111;
    /// HEMI on Hemi mainnet (18 decimals)
    address constant HEMI_TOKEN = 0x99e3dE3817F6081B2568208337ef83295b7f591D;

    function run() external {
        address rewardsSigner = vm.envAddress("REWARDS_SIGNER");
        address token = vm.envOr("REWARD_TOKEN", address(0));
        bool mainnet = block.chainid == HEMI_MAINNET;
        if (mainnet) {
            if (token == address(0)) token = HEMI_TOKEN;
            require(token == HEMI_TOKEN, "On Hemi mainnet the first reward token must be HEMI");
        }

        vm.startBroadcast();
        address owner = vm.envOr("REWARDS_OWNER", msg.sender);

        bool testToken = token == address(0);
        if (testToken) {
            TestHemiToken test = new TestHemiToken(msg.sender);
            token = address(test);
            console.log("Test token (tHEMI):", token);
        }

        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = IERC20(token);
        AshfallRewards rewards = new AshfallRewards(rewardsSigner, owner, tokens);
        AshfallSaves saves = new AshfallSaves();

        if (testToken) {
            uint256 budget = vm.envOr("TEST_BUDGET", uint256(100_000 ether));
            TestHemiToken(token).mint(address(rewards), budget);
        }
        vm.stopBroadcast();

        console.log("Rewards contract:", address(rewards));
        console.log("Saves contract:", address(saves));
        console.log("Reward token:", token);
        console.log("Signer:", rewardsSigner);
        console.log("Owner:", owner);
        if (!testToken) {
            console.log("Next: send the HEMI budget to the rewards contract and put both addresses in wrangler.jsonc");
        }
    }
}
