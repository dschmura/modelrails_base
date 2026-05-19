# Deployment

> **This page has moved.**
>
> The canonical deployment guide now lives in the in-app markdowndocs surface at **[`/docs/deployment`](/docs/deployment)** (rendered from [`app/docs/deployment.md`](../app/docs/deployment.md)).
>
> The in-app version is more complete: it covers Kamal topology + the SQLite single-host constraint, the `SOLID_QUEUE_IN_PUMA` graduation checklist, `max-replicas: 1` and `stop_wait_time: 45` rationale, builder-arg Ruby version pass-through, SSL configuration, storage volume + backup guidance, and a troubleshooting table. Every fork inherits it automatically via the markdowndocs engine.

## Why two surfaces?

Static repo docs at `docs/` are useful for GitHub-browsing readers who haven't cloned the repo yet. The in-app surface at `/docs/` is what runs inside every fork — that's where deploy guidance needs to live so forkers find it without leaving their app. After this page was reduced to a stub, **the in-app surface is canonical**; this file exists only as a redirect for incoming links.

If you've landed here from an external link, please update the link to point at the live in-app docs of your fork's deployed instance.
