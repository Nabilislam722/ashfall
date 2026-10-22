# Hemi on-chain features: exchange, saves and staking

Three things in the game happen on the Hemi network, through the player's
browser wallet (so only in the web build):

| Feature | Where | Contract |
| --- | --- | --- |
| **Hemi Exchange**: trade gold for HEMI (10 gold = 1 HEMI) | Nova's stall in Willowbrook | `AshfallRewards` (ours) |
| **On-chain saves**: checkpoints save the journey; Continue / New Game on the title screen | every checkpoint | `AshfallSaves` (ours) |
| **Mana Well**: stake HEMI for veHEMI; veHEMI raises the Storm Staff's mana capacity | Vera's stall by the north gate, open after Rick is beaten | official veHemi |

The ☰ menu in the page's top bar (`web/menu.js`; M in the game opens it too)
connects the wallet, switches it to Hemi (adding the network if needed), and
can switch back or disconnect later. Nova's and Vera's windows show the same
wallet. Connecting works even when the game server is offline.

## Network and contracts

| | |
| --- | --- |
| Network | Hemi mainnet, chain ID 43111 |
| Gas token | ETH |
| RPC URL | https://rpc.hemi.network/rpc |
| Block explorer | https://explorer.hemi.xyz |
| HEMI token | `0x99e3dE3817F6081B2568208337ef83295b7f591D` (18 decimals) |
| veHemi (staking) | `0x371d3718D5b7F75EAb050FAe6Da7DF3092031c89` |
| AshfallRewards | yours, from `contracts/script/Deploy.s.sol` |
| AshfallSaves | yours, from the same script |

## Security model: read this before using real HEMI

The game runs entirely in the player's browser. **Anything the game reports
can be faked**: gold, progress, saves. Nothing on the client can prevent that,
so nothing of value trusts the client. What a cheater can get is bounded on
the server and the chain:

- **Gold only counts once it is saved on-chain.** The exchange reads the
  wallet's save from `AshfallSaves` itself and only pays gold "earned" in
  the current journey (a journey, or run, starts with New Game).
- **Each save is cashed in once.** After an exchange, only a newer on-chain
  save counts, and the journey's ledger remembers what was already exchanged.
  Exiting and continuing from the same checkpoint can't exchange the same gold
  again (in the game the gold stays spent too).
- **One consistent ledger.** Every balance lives in a single Durable Object
  (`cloudflare/ledger.js`) that handles one request at a time with strongly
  consistent storage, so a signed sign-in works exactly once and two exchanges
  can never both see the same balance. (An earlier version used Workers KV,
  which is eventually consistent: sending one signed request several times at
  once could be booked several times.)
- **Per journey**: at most `RUN_GOLD_LIMIT` gold (200), minus what was already
  exchanged in that journey. The dungeon's monsters respawn and their ears sell
  for gold at the Adventurers' Guild, so a player can farm as much gold as they
  like for the shops, but no more than this ever turns into HEMI per journey.
- **Over time**: a journey's gold unlocks at `GOLD_PER_MINUTE` (10 per minute)
  from the run's start, which the chain stamps when New Game is pressed. Nobody
  can backdate it, so even a scripted cheater has to wait about 20 minutes per
  journey.
- **Per wallet, for ever**: at most `WALLET_CAP_GOLD` (500 gold = 50 HEMI),
  across all journeys. New Game never resets it.
- **All wallets per day**: at most `DAILY_CAP_GOLD` (20,000 gold = 2,000 HEMI).
- **Contract budget**: the rewards contract only pays from the tokens you send
  it. That is your real maximum loss; fund it with what you are happy to give away.
- **Wallet signatures**: the exchange only credits wallets that sign a fresh
  challenge, so nobody can use up someone else's allowance.
- **Cumulative vouchers**: replaying, duplicating or racing vouchers can never
  pay more than the latest total.
- **Signer key holds no funds**: if the Worker secret leaks, call
  `setSigner(newAddress)` and `pause()` if needed.

What remains: one person with many wallets can collect the per-wallet limit
once per wallet, slowly. If that matters at your scale, lower the caps, add
Cloudflare Turnstile to `/challenge`, or require a minimum wallet age or
balance. Single-player things (mana, health, damage) only affect the cheater
and are not worth defending. Token giveaways may have legal or tax implications
where you or your players live.

## Hemi Exchange

```text
game (Lua)  --webBridge.lua-->  web/bridge.js  --fetch-->  Worker /game/api/hemi/*
                                     |                         | reads the save, signs a voucher
                                     v                         v
                              browser wallet  --claim tx-->  AshfallRewards  --> HEMI to player
```

1. **Prove the wallet**: the Worker issues a one-time message; the player signs
   it (free, no gas).
2. **Voucher**: the Worker reads the wallet's on-chain save, works out how much
   gold it may take now (limits above), credits it and signs an EIP-712 voucher
   for the wallet's *total* credit in that token. The signing domain (name,
   version) is read from the rewards contract itself (EIP-5267), so vouchers
   match whichever deployment `REWARDS_CONTRACT` points at, including one
   deployed under the game's earlier name, `LegendOfLuaRewards`.
3. **Claim**: the player sends `claim(token, total, deadline, signature)` and
   pays the gas (a fraction of a cent on Hemi). The contract pays
   `total - alreadyClaimed`.

The window shows "Exchangeable now" and, when nothing is, why (no save yet,
gold still unlocking, journey used up, wallet limit). The game takes gold out
as soon as the Worker credits it; if the player cancels the transaction the
tokens stay reserved and pressing E later claims them. Gold exchanged after a
save is taken off again when that save is loaded.

### More tokens later

`AshfallRewards` pays any token the owner allows, from the same contract:

```powershell
cast send <rewards> "setTokenAllowed(address,bool)" <token> true --account deployer --rpc-url hemi
cast send <token> "transfer(address,uint256)" <rewards> <amount> --account deployer --rpc-url hemi
```

Each token keeps its own tally per player, and a voucher for one token can't be
spent in another. The Worker currently signs vouchers for `REWARD_TOKEN` (the
gold exchange); a new reward (an event, another stall) needs its own signing
rule on the server, and the contract needs no change.

## On-chain saves

Touching a checkpoint lights it and saves the journey; pressing E at a lit
checkpoint saves again. Every save goes to `save.json` on this device and, with
a wallet connected, to the wallet's slot in `AshfallSaves` (one wallet
confirmation, a tiny gas fee). The title screen offers **Continue**, which loads
the newer of the two, and **New Game**, which asks first, then clears the
on-chain slot with `newGame()` (one confirmation) before starting over.

`AshfallSaves` is deliberately minimal:

- only a wallet itself can write or wipe its own slot; there is **no owner, no
  pause and no upgrade**, so nobody, including you, can change a player's save;
- it holds no tokens or ETH;
- saves are capped at 4,096 bytes (the game writes about 500);
- every save names its run, so a save sent before New Game can't overwrite the
  new journey;
- the chain stamps the run's start and each save's time.

Loading treats a save as untrusted input: unknown maps, items the player
doesn't own, out-of-range numbers and unknown fields fall back to safe
defaults (`src/levels/saveState.lua`).

## Mana Well (veHEMI staking)

After Rick is beaten, the Elder points the player to Vera, and players who
never got the Storm Staff receive it. At Vera's stall the player picks an
amount (10 HEMI or more) and a lock (13 days to 4 years); staking sends two
transactions from their wallet to the official veHemi contract: `approve`, then
`createLock(amount, duration)`. The window asks twice and says plainly that
**locked HEMI can't be withdrawn until the lock ends**.

veHEMI is about `amount × lock / 4 years` and fades as the unlock date nears.

The player has one mana pool, shared by the fireball (E, 20 mana), the
Shift+click flame (10 mana) and the Storm Staff (releases everything in the
pool). It refills slowly on its own (4 mana per second, a little more with a
bigger pool, after a 1.2 second pause) and much faster while the staff is held.
Its capacity is

```text
capacity = 100 + min(200, floor(40 × log10(1 + veHEMI)))
```

The bonus only counts once Rick is beaten. Every 10× more veHEMI adds another
40 mana, so small holders feel it and whales can't break the game:

| veHEMI | 10 | 100 | 1,000 | 10,000 | 23,591 | 100,000+ |
| --- | --- | --- | --- | --- | --- | --- |
| extra mana | +41 | +80 | +120 | +160 | +174 | +200 (max) |

Because of the log scale, a small stake on top of a big balance can add
nothing: the window shows how much veHEMI the next point of mana needs. The
bonus reads the connected wallet's veHEMI across up to 30 locks, from the
public RPC.

## Setup

Tools: Node 18+, [Foundry](https://book.getfoundry.sh/) (`forge`, `cast`,
`anvil`), Wrangler.

```powershell
npm install                                           # viem + OpenZeppelin
cd contracts
forge install foundry-rs/forge-std --no-git           # test library (git-ignored)
forge test                                            # 39 contract tests
cd ..
```

### 1. Create the voucher signing key

```powershell
cast wallet new
```

Keep the private key for step 4. The address is the `REWARDS_SIGNER`. This key
only signs vouchers and should never hold funds.

### 2. Deploy both contracts on Hemi mainnet

Your deployer wallet needs a little ETH on Hemi for gas. On chain 43111 the
rewards contract starts with HEMI allowed, and the script refuses any other
first token.

```powershell
cast wallet import deployer --interactive             # store your deployer key encrypted
cd contracts
$env:REWARDS_SIGNER = "0x<signer address from step 1>"
forge script script/Deploy.s.sol --rpc-url hemi --account deployer --broadcast
cd ..
```

Note the printed `Rewards contract` and `Saves contract` addresses. The deployer
owns the rewards contract (set `REWARDS_OWNER` for another owner, such as a
multisig). The saves contract has no owner.

### 3. Fund the rewards contract with HEMI

```powershell
cast send 0x99e3dE3817F6081B2568208337ef83295b7f591D "transfer(address,uint256)" 0x<rewards contract> (cast to-wei 1000) --account deployer --rpc-url hemi
cast call 0x<rewards contract> "budget(address)(uint256)" 0x99e3dE3817F6081B2568208337ef83295b7f591D --rpc-url hemi
```

### 4. Configure the Worker

In `wrangler.jsonc`, set `REWARDS_CONTRACT` and `SAVES_CONTRACT` (the chain,
token, rate, limits, veHemi address and the ledger's Durable Object are already
set; Wrangler creates the Durable Object on deploy), then:

```powershell
npx wrangler secret put SIGNER_PRIVATE_KEY    # paste the signer private key from step 1
```

On-chain saves work as soon as `SAVES_CONTRACT` is set. The exchange opens
once the rewards contract and the secret are set too; until then the stall
says it is closed and everything else works.

### 5. Build and deploy

```powershell
pwsh -File scripts/build-web.ps1
npx wrangler deploy
```

### Optional: rehearse on Hemi Sepolia first

There is no testnet HEMI or veHemi. On Hemi Sepolia (chain 743111) the deploy
script creates a worthless stand-in token (tHEMI) and funds the rewards
contract with 100,000 of it; the Mana Well says staking needs Hemi mainnet.
Deploy with `--rpc-url hemi_sepolia` and no `REWARD_TOKEN`, set
`HEMI_CHAIN_ID` = `743111`, `REWARD_TOKEN` = the test token and
`REWARD_TOKEN_SYMBOL` = `tHEMI`. Before switching back to mainnet, rename the
Durable Object binding's class tag (a new `migrations` entry) or deploy under a
new Worker name, so testnet balances don't carry over.

## Operating the rewards contract

All owner functions: `cast send <rewards> "<fn>" ... --account deployer --rpc-url hemi`

- `withdrawAll(address token, address to)`: take a token's whole budget back.
- `withdrawAllTokens(address[] tokens, address to)`: empty several tokens at once.
- `withdraw(address token, address to, uint256 amount)`: take part of a budget back.
- `withdrawEther(address to)`: recover ETH forced into the contract (it never needs any).
- `setTokenAllowed(address token, bool allowed)`: start or stop paying a token.
- `pause()` / `unpause()`: stop or resume all claims.
- `setSigner(address)`: rotate the voucher key (invalidates outstanding vouchers).
- Views: `claimed(token, player)`, `totalClaimed(token)`, `budget(token)`, `tokenAllowed(token)`.

Ownership moves in two steps (`transferOwnership` + `acceptOwnership`), and
`renounceOwnership` is disabled so the budget can never be locked in for good.

## Tests

- `forge test` in `contracts/`: 25 rewards tests (payouts, cumulative top-ups,
  replays, wrong signer, inflated amounts, expiry, budget exhaustion, several
  tokens, a voucher for one token spent in another, withdraw all, owner-only
  functions, renounce disabled, fuzz) and 14 saves tests (only your own slot,
  New Game, stale saves after New Game, size limits, run start can't move, fuzz).
- `tests/hemi-exchange.e2e.mjs`: the real `bridge.js`, Worker API and both
  contracts on a local `anvil` chain: no save means no exchange, gold unlocking
  over time, the per-journey and per-wallet limits, New Game, a stale save,
  forged signatures, tampered vouchers, and cancelling then claiming later.
  Setup is at the top of the file.
- `tests/exchange-ledger.test.mjs`: replay and double-spend attempts against
  the ledger, with plain `node`: exchanging the same save twice, one signed
  request sent many times at once, reusing a sign-in, New Game farming against
  the wallet cap, and the time unlock.
- `tests/vehemi-stake.fork.mjs`: staking through the real `bridge.js` against
  the real veHemi and HEMI contracts on a local fork of Hemi mainnet.
- `tests/wallet-network.test.mjs`: switching to Hemi and disconnecting, with
  plain `node`.

## Files

| Path | Role |
| --- | --- |
| `contracts/src/AshfallRewards.sol` | Voucher-based payouts in any allowed token |
| `contracts/src/AshfallSaves.sol` | One save slot per wallet, no admin |
| `contracts/src/TestHemiToken.sol` | Testnet stand-in token (tHEMI) |
| `contracts/script/Deploy.s.sol` | Deploys both contracts |
| `cloudflare/hemiRewards.js` | Worker API: challenge, limits from the on-chain save, voucher signing |
| `cloudflare/ledger.js` | The exchange ledger (Durable Object): sign-ins and every balance |
| `web/bridge.js` | Wallet, exchange, saves and staking in the page, polled from Lua |
| `web/menu.js` | ☰ menu in the page's top bar |
| `src/utilities/webBridge.lua` | Lua side of the bridge |
| `src/utilities/onchain.lua` | Runs the game's on-chain requests one at a time |
| `src/levels/saveState.lua` | Save snapshots, validation, device and on-chain saving |
| `src/ui/menu.lua` | Title screen: Continue / New Game |
| `src/ui/hemiExchange.lua` | Nova's exchange window |
| `src/ui/manaWell.lua` | Vera's staking window |
| `src/items/staff.lua` | Storm Staff, mana capacity from veHEMI |
