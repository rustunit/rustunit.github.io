+++
title = "Building ezli.me, a link shortener in Rust"
date = 2026-04-17
[extra]
tags = ["rust","web","infra"]
hidden = true
custom_summary = "A small Rust link shortener with PostgreSQL, in-memory caching and batched click writes."
+++

In this short post we introduce [ezlime](https://github.com/rustunit/ezlime), the small Rust service behind [ezli.me](https://ezli.me).

# Why we built this

We built it for a pretty boring reason. On [Live-Ask.com](https://www.live-ask.com) we used [TinyURL](https://tinyurl.com) to shorten event links, and after they tightened their free tier we were about to outgrow it.

Paying for another SaaS plan would have solved that. But we already run a small K3s cluster with spare capacity, so at that point the question became: how much software do we actually need to redirect a URL?

Not much, as it turns out. We wanted:

* instant redirects
* a simple link creation API
* minimal stats: click count and last used
* a setup small enough that self-hosting stays worth it

# How it works

A request comes in, we check an in-memory cache, fall back to Postgres on a miss, and bump a click counter in memory. A background task batches those counters to the database every few seconds. That is the entire request lifecycle.

# What actually runs

The service is using `axum`, `tokio` and PostgreSQL. Database access goes through `diesel`, and migrations are baked into the binary.

For redirects we keep hot links in an in-memory [`quick_cache`](https://crates.io/crates/quick_cache), so popular IDs usually do not hit the database at all. Public link creation goes through [Cloudflare Turnstile](https://developers.cloudflare.com/turnstile/). Authenticated clients can use API keys. There is no account system and no tracking.

In production this runs as two replicas in our K3s cluster with `10m` CPU / `32Mi` memory requests and `100m` CPU / `128Mi` memory limits. The landing page at [ezli.me](https://ezli.me) is plain static HTML/CSS.

# The hot path

The redirect handler is intentionally tiny:

```rust
pub async fn redirect(&self, id: &str) -> Result<String, anyhow::Error> {
    if id.contains(".") || id.is_empty() {
        anyhow::bail!("invalid id");
    }

    if let Some(link) = self.cache.get(id) {
        self.click_counter.increment(id).await;
        return Ok(link.clone());
    }

    let Some(link) = self.db.get(id).await? else {
        anyhow::bail!("unknown link")
    };

    self.cache.insert(id.to_string(), link.url.clone());
    self.click_counter.increment(id).await;

    Ok(link.url)
}
```

There are only two real cases here. On a cache hit we return immediately and only bump an in-memory counter. On a miss we do one database lookup, put the result into the cache, and return that.

The important part is what does not happen on the request path: a click does not become a Postgres write.

# Keeping writes off the request path

`ClickCounter` accumulates click counts and `last_used` timestamps in memory. A background task drains that state and flushes it to Postgres every few seconds:

```rust
pub async fn start_counter_flusher(
    counter: Arc<ClickCounter>,
    db: DbPool,
    interval_duration: Duration,
) {
    let mut ticker = interval(interval_duration);
    loop {
        ticker.tick().await;

        let counts = counter.drain().await;
        if counts.is_empty() {
            continue;
        }

        if let Err(e) = flush_counts_to_db(db.clone(), counts).await {
            tracing::error!("failed to flush click counts: {e}");
        }
    }
}
```

Flushing means one bulk `UPDATE` query:

```sql
UPDATE links AS l
SET
    click_count = l.click_count + v.inc,
    last_used   = GREATEST(l.last_used, v.ts)
FROM (
    SELECT
        unnest(link_ids)  AS link_id,
        unnest(increments) AS inc,
        unnest(timestamps) AS ts
) AS v
WHERE l.id = v.link_id;
```

If one link gets clicked a thousand times in 3 seconds, that still becomes one row update in the next flush, not a thousand separate writes.

> `GREATEST` on `last_used` also makes concurrent flushing across replicas safe. A slower replica cannot clobber a newer timestamp from another one.

There is nothing fancy here, which is exactly the point. The hot path stays small, the write path stays cheap, and there is very little to reason about in production.

# Short IDs

Short IDs are deterministic. We hash the original URL and base62-encode it, so the same URL gets the same short code. If two different URLs collide, we retry with an offset in the hash input until they no longer do.

# Small footprint

This is the part that made it worth building for us. The running system is:

* one Rust binary
* one Postgres database
* one small K3s deployment in infrastructure we already have

There is no Redis, no queue, no analytics pipeline and no admin backend. We get tracing logs, Prometheus metrics and a health endpoint and call it a day.

That is when self-hosting starts to make sense: when the service just slots into the platform you already run instead of dragging more infrastructure behind it.

# Conclusion

ezli.me only makes sense for us because the rest of the platform is already there. Once that box is checked, a link shortener really is just Rust, Postgres, an in-memory cache and a tiny K3s deployment.

The project is on [GitHub](https://github.com/rustunit/ezlime), dual-licensed MIT / Apache-2.0. If you want to run your own, give it a try.

---

Want to use the hosted ezli.me API? Join our [Discord](https://discord.gg/MHzmYHnnsE) and reach out to get an API key.
