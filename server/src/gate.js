// Gate: one Durable Object per key, for counts that must be exact (KV is eventually consistent and
// D1 has a single writer, so neither suits a counter hit on every request). A key is a rate limit
// ("rl:share:<device>"), a device's nonces ("nonce:<device>") or one share ("share:<id>": its views
// and wrong passwords).
import { DurableObject } from "cloudflare:workers";

// Wrong passwords for one share: free for the first few, then each waits twice as long; at most
// HOURLY an hour, and LOCK_AT in all locks the link for good (the owner shares it again).
const FREE = 5, HOURLY = 20, LOCK_AT = 100;

export class Gate extends DurableObject {
  /** Fixed-window limit: true while fewer than `limit` hits fell in this `window` seconds. */
  async hit(limit, window, cost = 1) {
    const t = Date.now() / 1000;
    let w = (await this.ctx.storage.get("w")) || { start: t, n: 0 };
    if (t - w.start >= window) w = { start: t, n: 0 };
    if (w.n + cost > limit) return { ok: false, retryAfter: Math.ceil(w.start + window - t) };
    w.n += cost;
    await this.ctx.storage.put("w", w);
    await this.expireIn(window);
    return { ok: true };
  }

  /** False when this nonce was already used (a replayed request). Nonces are kept for `ttl` seconds. */
  async fresh(nonce, ttl) {
    const key = "n:" + nonce;
    if (await this.ctx.storage.get(key)) return false;
    await this.ctx.storage.put(key, Date.now() + ttl * 1000);
    await this.expireIn(ttl);
    return true;
  }

  async view() {
    const v = ((await this.ctx.storage.get("views")) || 0) + 1;
    await this.ctx.storage.put("views", v);
    return v;
  }

  async stats() {
    const a = (await this.ctx.storage.get("attempts")) || { fails: 0 };
    return { views: (await this.ctx.storage.get("views")) || 0, wrongPasswords: a.fails, locked: a.fails >= LOCK_AT };
  }

  /** May a password be tried now? */
  async mayTry() {
    const t = Date.now() / 1000;
    const a = (await this.ctx.storage.get("attempts")) || { fails: 0, last: 0, hour: t, inHour: 0 };
    if (a.fails >= LOCK_AT) return { ok: false, locked: true };
    if (t - a.hour >= 3600) { a.hour = t; a.inHour = 0; }
    if (a.inHour >= HOURLY) return { ok: false, retryAfter: Math.ceil(a.hour + 3600 - t) };
    const wait = a.fails < FREE ? 0 : Math.min(3600, 2 ** (a.fails - FREE));
    if (t - a.last < wait) return { ok: false, retryAfter: Math.ceil(a.last + wait - t) };
    return { ok: true };
  }

  async tried(right) {
    const t = Date.now() / 1000;
    const a = (await this.ctx.storage.get("attempts")) || { fails: 0, last: 0, hour: t, inHour: 0 };
    if (t - a.hour >= 3600) { a.hour = t; a.inHour = 0; }
    if (!right) { a.fails += 1; a.inHour += 1; a.last = t; }
    await this.ctx.storage.put("attempts", a);
  }

  /**
   * One Jev call, made from here rather than the Worker: ZenMux answers 451 to requests that leave
   * Cloudflare near mainland China, and a Worker runs next to its visitor. The review objects are
   * created in North America (see `askJev` below), so the call always leaves from there.
   */
  async jev(body) {
    const r = await fetch("https://zenmux.ai/api/v1/systemone", {
      method: "POST",
      headers: { Authorization: "Bearer " + this.env.ZENMUX_API_KEY, "Content-Type": "application/json" },
      body,
      signal: AbortSignal.timeout(15000),
    });
    return { status: r.status, text: r.ok ? await r.text() : "" };
  }

  /** Forget the share (it was revoked or expired). */
  async clear() {
    await this.ctx.storage.deleteAll();
  }

  async expireIn(seconds) {
    const at = Date.now() + seconds * 1000 + 60_000;
    const current = await this.ctx.storage.getAlarm();
    if (!current || current < at) await this.ctx.storage.setAlarm(at);
  }

  /** Rate-limit windows and nonces are short-lived: drop what has run out. Share counters stay. */
  async alarm() {
    const t = Date.now();
    const items = await this.ctx.storage.list();
    for (const [key, value] of items) {
      if (key.startsWith("n:") && value < t) await this.ctx.storage.delete(key);
    }
    const w = items.get("w");
    if (w && t / 1000 - w.start > 86400) await this.ctx.storage.delete("w");
  }
}

/** Jev via one of a few review objects pinned to North America. → { status, text } */
export function askJev(env, body) {
  const name = "jev-us-" + Math.floor(Math.random() * 4);
  return env.GATE.get(env.GATE.idFromName(name), { locationHint: "enam" }).jev(body);
}

export function gate(env, key) {
  return env.GATE.get(env.GATE.idFromName(key));
}

/** A rate limit as the routes use it: null when allowed, else the 429 to send. */
export async function limit(env, key, max, window, cost = 1) {
  const r = await gate(env, "rl:" + key).hit(max, window, cost);
  return r.ok ? null : r.retryAfter;
}
