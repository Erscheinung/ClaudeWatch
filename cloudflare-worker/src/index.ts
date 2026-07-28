export interface Env {
  ALLOWED_ORIGIN?: string;
  REQUESTS_PER_MINUTE?: string;
}

const FREE_GATEWAY_URL = "https://text.pollinations.ai/openai";
const FREE_MODELS = new Set(["openai"]);

const requests = new Map<string, { count: number; resetAt: number }>();

function corsHeaders(env: Env): HeadersInit {
  return {
    "Access-Control-Allow-Origin": env.ALLOWED_ORIGIN || "*",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type",
  };
}

function response(body: string, status: number, env: Env): Response {
  return new Response(body, { status, headers: { "Content-Type": "application/json", ...corsHeaders(env) } });
}

function withinRateLimit(request: Request, env: Env): boolean {
  const client = request.headers.get("CF-Connecting-IP") || "unknown";
  const now = Date.now();
  const limit = Number(env.REQUESTS_PER_MINUTE || "20");
  const entry = requests.get(client);
  if (!entry || entry.resetAt <= now) {
    requests.set(client, { count: 1, resetAt: now + 60_000 });
    return true;
  }
  entry.count += 1;
  return entry.count <= limit;
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    if (request.method === "OPTIONS") return new Response(null, { headers: corsHeaders(env) });
    const url = new URL(request.url);
    if (request.method !== "POST" || url.pathname !== "/v1/chat/completions") {
      return response(JSON.stringify({ error: { message: "Not found" } }), 404, env);
    }
    if (!withinRateLimit(request, env)) {
      return response(JSON.stringify({ error: { message: "Rate limit exceeded" } }), 429, env);
    }

    let body: { model?: string; messages?: unknown[]; max_tokens?: number; temperature?: number };
    try {
      body = await request.json();
    } catch {
      return response(JSON.stringify({ error: { message: "Invalid JSON" } }), 400, env);
    }
    if (!body.model || !FREE_MODELS.has(body.model) || !Array.isArray(body.messages)) {
      return response(JSON.stringify({ error: { message: "Unsupported free-cloud model" } }), 400, env);
    }

    const upstream = await fetch(FREE_GATEWAY_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: body.model,
        messages: body.messages,
        max_tokens: Math.min(Math.max(Number(body.max_tokens) || 180, 1), 180),
        temperature: typeof body.temperature === "number" ? body.temperature : 0.4,
      }),
    });

    return new Response(upstream.body, {
      status: upstream.status,
      headers: {
        "Content-Type": upstream.headers.get("Content-Type") || "application/json",
        ...corsHeaders(env),
      },
    });
  },
};
