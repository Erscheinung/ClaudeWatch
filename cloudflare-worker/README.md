# ClaudeWatch Free Cloud Gateway

This optional Worker forwards ClaudeWatch's verified anonymous free route and applies a basic edge-side rate limit. It is OpenAI-compatible.

## Deploy

```bash
cd cloudflare-worker
npm install
npx wrangler login
npm run deploy
```

Copy the deployed `https://<worker>.<account>.workers.dev` URL into **Settings > Free Cloud Gateway** on the Watch. Do not append `/v1/chat/completions`; the app adds it.

The Worker uses a best-effort in-memory, per-IP rate limit. For a public deployment, additionally protect the route with Cloudflare WAF/rate-limit rules or replace the limiter with a Durable Object. The upstream anonymous route can change its limits or availability without notice.
