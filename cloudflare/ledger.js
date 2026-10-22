// The exchange ledger: a single Durable Object holding every account the Hemi
// Exchange keeps (challenges, gold credited per wallet and token, gold
// exchanged per journey, the daily budget).
//
// A Durable Object handles one request at a time and its storage is strongly
// consistent, so these checks can't be raced: a signed challenge works exactly
// once, and two exchanges can never both see the same balance. (Workers KV,
// used before, is eventually consistent and can serve stale reads for up to a
// minute.) All slow work (verifying the wallet signature, reading the save from
// the chain) happens in the Worker before it calls in here; the ledger itself
// only reads and writes its storage.

const CHALLENGE_TTL_MS = 5 * 60 * 1000;

function json(body) {
  return new Response(JSON.stringify(body), { headers: { "content-type": "application/json" } });
}

function wholeGold(value) {
  const n = Math.floor(Number(value));
  return Number.isFinite(n) && n > 0 ? n : 0;
}

export class ExchangeLedger {
  constructor(state) {
    this.storage = state.storage;
  }

  async fetch(request) {
    const body = await request.json();
    switch (body.op) {
      case "challenge":
        return json(await this.challenge(body));
      case "getChallenge":
        return json(await this.getChallenge(body));
      case "account":
        return json(await this.account(body));
      case "redeem":
        return json(await this.redeem(body));
      default:
        return json({ ok: false, error: "unknown ledger operation" });
    }
  }

  keys(body) {
    const wallet = String(body.address).toLowerCase();
    const token = String(body.token || "").toLowerCase();
    return {
      challenge: `challenge:${wallet}`,
      credited: `credited:${token}:${wallet}`,
      run: `run:${wallet}:${body.runId}`,
      usedSave: `usedSave:${wallet}:${body.runId}`,
      daily: `daily:${body.day}`,
    };
  }

  async challenge(body) {
    await this.storage.put(this.keys(body).challenge, { message: body.message, expires: body.now + CHALLENGE_TTL_MS });
    return { ok: true };
  }

  async getChallenge(body) {
    const stored = await this.storage.get(this.keys(body).challenge);
    if (!stored || stored.expires < body.now) return { ok: true, message: null };
    return { ok: true, message: stored.message };
  }

  // what the wallet has and may still exchange; never changes anything
  async state(body) {
    const k = this.keys(body);
    const credited = wholeGold(await this.storage.get(k.credited));
    const exchangedRun = body.runId ? wholeGold(await this.storage.get(k.run)) : 0;
    const usedSave = body.runId ? wholeGold(await this.storage.get(k.usedSave)) : 0;
    const usedToday = wholeGold(await this.storage.get(k.daily));
    const c = body.caps;
    const runCap = Math.min(wholeGold(body.earned), c.run, wholeGold(body.unlocked));
    // each save can be cashed in once: after an exchange, a newer save is needed
    const staleSave = exchangedRun > 0 && wholeGold(body.saveCount) <= usedSave;
    const rooms = {
      save: body.hasSave ? Infinity : 0,
      stale: staleSave ? 0 : Infinity,
      run: Math.max(0, Math.min(wholeGold(body.earned), c.run) - exchangedRun),
      time: Math.max(0, wholeGold(body.unlocked) - exchangedRun),
      wallet: Math.max(0, c.wallet - credited),
      daily: Math.max(0, c.daily - usedToday),
    };
    const available = Math.max(0, Math.min(runCap - exchangedRun, rooms.save, rooms.stale, rooms.wallet, rooms.daily));
    return { k, credited, exchangedRun, usedToday, rooms, available };
  }

  async account(body) {
    const s = await this.state(body);
    return { ok: true, credited: s.credited, exchangedRun: s.exchangedRun, rooms: s.rooms, available: s.available };
  }

  async redeem(body) {
    const k = this.keys(body);
    // the challenge the Worker verified must still be the live one, and is used up now
    const stored = await this.storage.get(k.challenge);
    if (!stored || stored.message !== body.message || stored.expires < body.now) {
      return { ok: false, status: 401, error: "Your sign-in expired. Please try again." };
    }
    await this.storage.delete(k.challenge);

    const s = await this.state(body);
    const grant = Math.min(wholeGold(body.gold), s.available);
    const credited = s.credited + grant;
    if (grant > 0) {
      await this.storage.put(k.credited, credited);
      await this.storage.put(k.run, s.exchangedRun + grant);
      await this.storage.put(k.usedSave, wholeGold(body.saveCount));
      await this.storage.put(k.daily, s.usedToday + grant);
    }
    return { ok: true, grant, credited, exchangedRun: s.exchangedRun + grant, rooms: s.rooms, available: s.available };
  }
}
