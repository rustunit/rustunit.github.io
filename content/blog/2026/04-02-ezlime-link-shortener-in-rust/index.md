+++
title = "Building ezli.me, a link shortener in Rust"
date = 2026-04-02
[extra]
tags = ["rust","web","infra"]
hidden = true
custom_summary = "How ezli.me stays fast and cheap to run with a small Rust stack, in-memory caching and a minimal operational footprint."
+++

# Intro

* Open with the simple claim: a link shortener sounds trivial until you want it to be fast, cheap and boring to operate.
* Introduce [ezlime](https://github.com/rustunit/ezlime) as the software behind [ezli.me](https://ezli.me).
* Frame the post around three questions:
  * what the stack looks like
  * why it is so fast
  * why it is so cheap to maintain
* Set up the Rust angle early: this is not about chasing benchmarks, it is about keeping a small service small.

# Why we built it

* Start with the concrete trigger: TinyURL reduced their free tier and we were about to hit the limit with Live-Ask.com
* Frame the real question like this: if we already run a K3s cluster with spare capacity, why not just run our own shortener there?
* Explain that this changed the problem from "which SaaS plan do we buy?" to "how small can we keep this service so self-hosting stays obviously worth it?"
* Mention the resulting design constraints:
  * instant redirects
  * simple link creation API
  * privacy-focused stats
  * tiny ops footprint
  * easy self-hosting inside existing infrastructure
* Make the contrast explicit: once you already have the cluster, the expensive part is no longer compute, it is operational complexity.

# The stack

* The backend is a small Rust service built with `axum` and `tokio`.
* Persistence is just PostgreSQL.
* The service uses `diesel` / `diesel-async` for database access and migrations.
* Redirects use an in-memory `quick_cache` so hot links do not need a database read every time.
* Public link creation is protected by Cloudflare Turnstile instead of a full user-account system.
* Authenticated API access is intentionally simple: API keys come from configuration, not from a separate auth service.
* The service runs in K3s behind ingress, with Prometheus metrics and normal tracing logs.
* Call out the tiny deployment shape:
  * two replicas
  * `10m` CPU / `32Mi` memory requests
  * `100m` CPU / `128Mi` memory limits
* Mention the optional extras without making them the center of the post:
  * `ezlime-rs` as a small Rust client crate
  * the `x402` endpoint for pay-per-use link creation
  * the landing page being plain static HTML/CSS/JS instead of a framework-heavy frontend

# Why it is fast

* The hot path for redirects is intentionally tiny.
* On a cache hit the service:
  * looks up the short id in memory
  * increments an in-memory counter
  * returns a redirect
* On a cache miss it is still simple:
  * one database read by short id
  * cache insert
  * redirect response
* Emphasize that click tracking does not block the redirect path on every request.
* Explain the batching trick:
  * clicks and `last_used` updates are accumulated in memory
  * a background task flushes them to Postgres every few seconds
  * Postgres applies them in a single batch function
* Mention deterministic id generation from a hash of the original URL:
  * same URL can resolve to the same short code
  * collisions are handled by retrying with an offset
* Good snippet candidates:
  * `App::redirect`
  * `ClickCounter`
  * the Postgres `batch_update_clicks` function

# Why it is cheap to maintain

* This is where the post should become very concrete.
* The central point is not just that the service is lightweight. It is that it fits into infrastructure we already run anyway.
* The service has very few moving parts:
  * one Rust binary
  * one Postgres database
  * one small Kubernetes deployment in the existing cluster
* No Redis.
* No message broker.
* No analytics pipeline.
* No server-side rendered frontend.
* No admin backend or full account system.
* The database model is intentionally small:
  * links
  * a few counters / timestamps
  * optional payment metadata
* The public website is static, so there is no frontend build system that needs constant care.
* Self-hosting is straightforward because the runtime dependencies are straightforward and already match the rest of our stack.
* Observability is built in from the start:
  * tracing logs
  * Prometheus metrics
  * health endpoint
* Testing story is also part of maintenance cost:
  * DB logic sits behind a trait
  * unit tests can mock the DB
  * integration tests use Postgres testcontainers
* Nice angle for this section: the cheapest service to maintain is usually the one that can be absorbed by your existing platform instead of demanding a new one.

# Why Rust was a good choice

* Do not make this a generic "Rust is fast" section. Keep it grounded in this service.
* Good points to hit:
  * low baseline CPU and memory use for an always-on web service
  * async networking without a lot of runtime overhead
  * strong typing around request handling, database boundaries and background tasks
  * easy to keep the whole service as a single deployable binary
  * testability through traits and explicit state
* Mention that a redirect service is mostly simple I/O, which is exactly where Rust feels good:
  * lots of concurrent small requests
  * very little wasted work
  * predictable resource usage
* Another good angle: Rust makes it comfortable to keep performance-sensitive code boring. The cache path, the counter flusher and the DB boundary are all explicit and easy to reason about.

# Suggested code snippets

* `App::redirect` to show the cache-first flow.
* `start_counter_flusher` plus the SQL batch update function.
* Router setup in `main.rs` to show how the service is split into:
  * public `Turnstile` flow
  * authenticated API flow
  * optional `x402` payment flow
* Deployment snippet showing how little CPU and memory the service asks for.

# Conclusion

* Close on the main point: ezli.me is fast and cheap not because it uses a complicated distributed design, but because it avoids one and slots into infrastructure we already have.
* Restate the stack in one line: Rust service, Postgres, cache, tiny K3s deployment in an existing cluster.
* Final Rust takeaway: Rust was a good choice because it let us keep performance high without growing the architecture or the maintenance burden.
* End with a pointer to the repo, the self-hosting angle, and the hosted-service CTA: join our Discord and reach out to get an API key.

---

Want to use the hosted ezli.me API? Join our [Discord](https://discord.gg/MHzmYHnnsE) and reach out to get an API key.
