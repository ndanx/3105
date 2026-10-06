import crypto from "node:crypto";

const accountID = process.env.KEYGEN_ACCOUNT_ID;
const keygenToken = process.env.KEYGEN_SERVER_TOKEN;
const appAccessToken = process.env.APP_ADMIN_TOKEN;

const rateWindowMs = 60_000;
const maxRequestsPerWindow = 60;
const requestCounts = new Map<string, { count: number; resetAt: number }>();

function response(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
    },
  });
}

function constantTimeEqual(left: string, right: string) {
  const a = Buffer.from(left);
  const b = Buffer.from(right);
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

function clientKey(request: Request) {
  return request.headers.get("x-forwarded-for")?.split(",")[0]?.trim() || "unknown";
}

function isRateLimited(request: Request) {
  const key = clientKey(request);
  const now = Date.now();
  const current = requestCounts.get(key);
  if (!current || current.resetAt <= now) {
    requestCounts.set(key, { count: 1, resetAt: now + rateWindowMs });
    return false;
  }
  current.count += 1;
  return current.count > maxRequestsPerWindow;
}

function authorized(request: Request) {
  if (!appAccessToken) return false;
  const header = request.headers.get("authorization") ?? "";
  const prefix = "Bearer ";
  return header.startsWith(prefix) && constantTimeEqual(header.slice(prefix.length), appAccessToken);
}

function keygenURL(path: string) {
  if (!accountID) return null;
  return `https://api.keygen.sh/v1/accounts/${encodeURIComponent(accountID)}${path}`;
}

async function keygenRequest(path: string, method: string, body?: unknown) {
  if (!keygenToken) return response({ error: "Server is not configured." }, 503);
  const url = keygenURL(path);
  if (!url) return response({ error: "Server is not configured." }, 503);
  const headers: Record<string, string> = {
    Accept: "application/vnd.api+json",
    Authorization: `Bearer ${keygenToken}`,
  };
  const init: RequestInit = { method, headers };
  if (body !== undefined) {
    headers["Content-Type"] = "application/vnd.api+json";
    init.body = JSON.stringify(body);
  }
  const upstream = await fetch(url, init);
  const text = await upstream.text();
  return new Response(text, {
    status: upstream.status,
    headers: { "Content-Type": "application/vnd.api+json", "Cache-Control": "no-store" },
  });
}

export default async function handler(request: Request) {
  const contentLength = Number(request.headers.get("content-length") ?? 0);
  if (contentLength > 10_000) return response({ error: "Request too large." }, 413);
  if (isRateLimited(request)) return response({ error: "Too many requests." }, 429);
  if (!authorized(request)) return response({ error: "Unauthorized." }, 401);

  try {
    if (request.method === "GET") {
      return keygenRequest("/licenses?limit=100", "GET");
    }

    if (request.method === "POST") {
      const body = await request.json();
      if (!body || typeof body !== "object" || typeof body.action !== "string") {
        return response({ error: "Invalid request." }, 400);
      }

      if (body.action === "create") {
        if (typeof body.policyID !== "string" || body.policyID.length > 200) {
          return response({ error: "A valid policy ID is required." }, 400);
        }
        const attributes: Record<string, string> = {};
        if (typeof body.name === "string" && body.name.trim()) {
          attributes.name = body.name.trim().slice(0, 120);
        }
        return keygenRequest("/licenses", "POST", {
          data: {
            type: "licenses",
            attributes,
            relationships: {
              policy: { data: { type: "policies", id: body.policyID.trim() } },
            },
          },
        });
      }

      if ((body.action === "suspend" || body.action === "reinstate") && typeof body.id === "string") {
        return keygenRequest(`/licenses/${encodeURIComponent(body.id)}/actions/${body.action}`, "POST");
      }
      return response({ error: "Invalid action." }, 400);
    }

    if (request.method === "DELETE") {
      const body = await request.json();
      if (!body || typeof body.id !== "string" || body.id.length > 200) {
        return response({ error: "A valid license ID is required." }, 400);
      }
      return keygenRequest(`/licenses/${encodeURIComponent(body.id)}/actions/revoke`, "DELETE");
    }

    return response({ error: "Method not allowed." }, 405);
  } catch {
    return response({ error: "Request failed." }, 400);
  }
}
