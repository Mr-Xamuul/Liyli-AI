const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const projectUrl = Deno.env.get("SUPABASE_URL") ?? "";
const secretKeys = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}") as Record<string, string>;
const serviceKey = secretKeys.default ?? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

type Row = Record<string, unknown>;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function serviceHeaders(extra: Record<string, string> = {}): HeadersInit {
  return {
    apikey: serviceKey,
    Authorization: `Bearer ${serviceKey}`,
    "Content-Type": "application/json",
    ...extra,
  };
}

async function serviceFetch(path: string, init: RequestInit = {}): Promise<Response> {
  return await fetch(`${projectUrl}${path}`, {
    ...init,
    headers: serviceHeaders(init.headers as Record<string, string> | undefined),
  });
}

async function serviceRows(path: string): Promise<Row[]> {
  const response = await serviceFetch(path);
  if (!response.ok) throw new Error(`Database request failed (${response.status})`);
  return (await response.json()) as Row[];
}

async function callVaultRpc(name: string, args: Row): Promise<unknown> {
  const response = await serviceFetch(`/rest/v1/rpc/${name}`, {
    method: "POST",
    body: JSON.stringify(args),
  });
  if (!response.ok) throw new Error(`Secret vault request failed (${response.status})`);
  const text = await response.text();
  return text ? JSON.parse(text) : null;
}

async function authenticate(req: Request): Promise<{ id: string; role: string } | null> {
  const authorization = req.headers.get("authorization");
  const publishableKey = req.headers.get("apikey");
  if (!authorization || !publishableKey) return null;
  const response = await fetch(`${projectUrl}/auth/v1/user`, {
    headers: { authorization, apikey: publishableKey },
  });
  if (!response.ok) return null;
  const user = (await response.json()) as { id?: string };
  if (!user.id) return null;
  const profiles = await serviceRows(
    `/rest/v1/profiles?select=role&id=eq.${encodeURIComponent(user.id)}&limit=1`,
  );
  return profiles.length ? { id: user.id, role: String(profiles[0].role ?? "student") } : null;
}

function requireAdmin(user: { role: string }): void {
  if (user.role !== "admin") throw new Error("Admin permission required");
}

function cleanBaseUrl(raw: unknown): string {
  const value = String(raw ?? "").trim().replace(/\/+$/, "");
  const url = new URL(value);
  if (url.protocol !== "https:" || url.username || url.password || url.search || url.hash) {
    throw new Error("Base URL-ku waa inuu noqdaa HTTPS URL sax ah.");
  }
  const host = url.hostname.toLowerCase();
  if (
    host === "localhost" || host.endsWith(".localhost") ||
    host === "127.0.0.1" || host === "::1" || host === "0.0.0.0" ||
    /^10\./.test(host) || /^192\.168\./.test(host) ||
    /^172\.(1[6-9]|2\d|3[01])\./.test(host) || host === "169.254.169.254"
  ) {
    throw new Error("Base URL gudaha/private network lama oggola.");
  }
  return value;
}

function vaultName(keyId: string): string {
  if (!/^[A-Za-z0-9_-]{1,120}$/.test(keyId)) throw new Error("API key ID-ga ma saxna.");
  return `leyli-ai-key:${keyId}`;
}

async function getKey(keyId: string): Promise<Row | null> {
  const rows = await serviceRows(
    `/rest/v1/ai_api_keys?select=id,name,provider,base_url,is_active,has_secret,notes&id=eq.${encodeURIComponent(keyId)}&limit=1`,
  );
  return rows[0] ?? null;
}

async function getSecret(keyId: string): Promise<string> {
  const value = await callVaultRpc("ai_vault_read_secret", { p_key_id: keyId });
  if (typeof value !== "string" || !value) throw new Error("API key ma hayo ama waa madhan.");
  return value;
}

async function listKeys(): Promise<Row[]> {
  return await serviceRows(
    "/rest/v1/ai_api_keys?select=id,name,provider,base_url,is_active,has_secret,notes,created_at,updated_at&order=created_at.asc",
  );
}

async function saveKey(payload: Row): Promise<Row> {
  const id = String(payload.id ?? "");
  vaultName(id);
  const name = String(payload.name ?? "").trim();
  const provider = String(payload.provider ?? "").trim();
  const baseUrl = cleanBaseUrl(payload.baseUrl);
  const secret = String(payload.apiKey ?? "").trim();
  if (!name || !provider) throw new Error("Magaca provider-ka iyo furaha waa waajib.");

  const existing = await getKey(id);
  if (secret) {
    await callVaultRpc("ai_vault_store_secret", {
      p_key_id: id,
      p_secret: secret,
      p_description: `${provider}: ${name}`,
    });
  } else if (!existing?.has_secret) {
    throw new Error("Furaha API-ga cusub geli ka hor intaadan kaydin.");
  }

  const row = {
    id,
    name,
    provider,
    base_url: baseUrl,
    is_active: payload.isActive !== false,
    has_secret: true,
    notes: String(payload.notes ?? "").trim(),
    updated_at: new Date().toISOString(),
  };
  const response = await serviceFetch("/rest/v1/ai_api_keys?on_conflict=id", {
    method: "POST",
    headers: { Prefer: "resolution=merge-duplicates,return=representation" },
    body: JSON.stringify(row),
  });
  if (!response.ok) throw new Error(`API key metadata lama kaydin (${response.status}).`);
  const saved = (await response.json()) as Row[];
  return saved[0] ?? row;
}

async function deleteKey(keyId: string): Promise<void> {
  vaultName(keyId);
  const response = await serviceFetch(`/rest/v1/ai_api_keys?id=eq.${encodeURIComponent(keyId)}`, {
    method: "DELETE",
  });
  if (!response.ok) throw new Error(`API key metadata lama tirtirin (${response.status}).`);
  await callVaultRpc("ai_vault_delete_secret", { p_key_id: keyId });
}

async function verifyKey(keyId: string): Promise<{ success: boolean; message: string }> {
  const key = await getKey(keyId);
  if (!key || key.is_active !== true || key.has_secret !== true) {
    return { success: false, message: "Furaha API-ga ma jiro ama ma shaqaynayo." };
  }
  const secret = await getSecret(keyId);
  const provider = String(key.provider).toLowerCase();
  const baseUrl = cleanBaseUrl(key.base_url);
  const isGoogle = provider.includes("google") || provider.includes("gemini");
  const url = isGoogle ? `${baseUrl}/v1beta/models` : `${baseUrl}/models`;
  const headers = isGoogle
    ? { "x-goog-api-key": secret }
    : { Authorization: `Bearer ${secret}` };
  const response = await fetch(url, { headers, redirect: "error", signal: AbortSignal.timeout(12000) });
  return response.ok
    ? { success: true, message: `Furaha ${key.name} waa sax oo shaqaynaya.` }
    : { success: false, message: `Xaqiijinta API-ga way fashilantay (HTTP ${response.status}).` };
}

async function verifyModel(payload: Row): Promise<{ success: boolean; message: string }> {
  const modelId = String(payload.modelId ?? "").trim();
  const keyId = String(payload.apiKeyId ?? "");
  const provider = String(payload.provider ?? "").toLowerCase();
  const key = await getKey(keyId);
  if (!modelId || !key || key.is_active !== true || key.has_secret !== true) {
    return { success: false, message: "Model ID ama API key sax ah lama helin." };
  }
  const baseUrl = cleanBaseUrl(payload.baseUrl);
  if (baseUrl !== cleanBaseUrl(key.base_url)) {
    return { success: false, message: "Base URL-ku waa inuu la mid noqdaa URL-ka furaha la doortay." };
  }
  const secret = await getSecret(keyId);
  const isGoogle = provider.includes("google") || provider.includes("gemini");
  let response: Response;
  if (isGoogle) {
    const body = payload.isTts === true
      ? {
          contents: [{ parts: [{ text: "Test" }] }],
          generationConfig: {
            responseModalities: ["AUDIO"],
            speechConfig: { voiceConfig: { prebuiltVoiceConfig: { voiceName: "Puck" } } },
          },
        }
      : { contents: [{ parts: [{ text: "Ping" }] }], generationConfig: { maxOutputTokens: 5 } };
    response = await fetch(
      `${baseUrl}/v1beta/models/${encodeURIComponent(modelId)}:generateContent`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json", "x-goog-api-key": secret },
        body: JSON.stringify(body),
        redirect: "error",
        signal: AbortSignal.timeout(25000),
      },
    );
  } else {
    response = await fetch(`${baseUrl}/chat/completions`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${secret}` },
      body: JSON.stringify({ model: modelId, messages: [{ role: "user", content: "Ping" }], max_tokens: 5 }),
      redirect: "error",
      signal: AbortSignal.timeout(25000),
    });
  }
  return response.ok
    ? { success: true, message: `Model-ka ${modelId} wuu shaqaynayaa.` }
    : { success: false, message: `Tijaabada model-ka way fashilantay (HTTP ${response.status}).` };
}

function parseStored(value: unknown): unknown {
  if (typeof value !== "string") return value;
  try { return JSON.parse(value); } catch { return value; }
}

async function getSetting(key: string): Promise<unknown> {
  const rows = await serviceRows(
    `/rest/v1/ai_admin_settings?select=setting_value&setting_key=eq.${encodeURIComponent(key)}&limit=1`,
  );
  return rows.length ? parseStored(rows[0].setting_value) : null;
}

async function proxyModel(user: { id: string; role: string }, payload: Row): Promise<Response> {
  const localModelId = String(payload.modelId ?? "");
  const operation = String(payload.operation ?? "chat");
  if (!localModelId || !["chat", "tts"].includes(operation)) throw new Error("AI request-ku ma saxna.");
  const modelSettingKey = operation === "tts" ? "saved_tts_models_v1" : "saved_ai_models_v1";
  const models = (await getSetting(modelSettingKey)) as Row[] | null;
  const model = models?.find((item) => item.id === localModelId);
  if (!model || model.isActive !== true || model.isVerified !== true || model.status !== "ready") {
    throw new Error("Model-kan lama hawlgelin ama lama xaqiijin.");
  }

  if (user.role !== "admin") {
    const routing = (await getSetting("ai_model_routing_config_v1")) as Row | null;
    const allowed = operation === "tts"
      ? (routing?.ttsModelIds as unknown[] | undefined)?.includes(localModelId)
      : (routing?.freeModelIds as unknown[] | undefined)?.includes(localModelId);
    if (!allowed) throw new Error("Model-kan ardayda uma furna.");
  }

  const keyId = String(model.apiKeyId ?? "");
  const key = await getKey(keyId);
  if (!key || key.is_active !== true || key.has_secret !== true) throw new Error("API key-ga model-kan ma shaqaynayo.");
  const secret = await getSecret(keyId);
  const provider = String(key.provider).toLowerCase();
  const isGoogle = provider.includes("google") || provider.includes("gemini");
  const baseUrl = cleanBaseUrl(key.base_url);
  const requestBody = (payload.body && typeof payload.body === "object") ? { ...(payload.body as Row) } : {};
  let url: string;
  let headers: Record<string, string> = { "Content-Type": "application/json" };
  if (isGoogle) {
    url = `${baseUrl}/v1beta/models/${encodeURIComponent(String(model.modelId))}:generateContent`;
    headers["x-goog-api-key"] = secret;
  } else if (operation === "chat") {
    url = baseUrl.endsWith("/chat/completions") ? baseUrl : `${baseUrl}/chat/completions`;
    headers.Authorization = `Bearer ${secret}`;
    requestBody.model = model.modelId;
  } else {
    throw new Error("TTS hadda waxa taageera provider-ka Google Gemini oo keliya.");
  }

  const budget = await callVaultRpc("ai_gateway_consume_budget", {
    p_user_id: user.id,
    p_is_admin: user.role === "admin",
  });
  if (budget !== true) {
    return json({ error: "Xadka isticmaalka AI-ga ayaa la gaaray. Fadlan mar kale isku day goor dambe." }, 429);
  }

  const upstream = await fetch(url, {
    method: "POST",
    headers,
    body: JSON.stringify(requestBody),
    redirect: "error",
    signal: AbortSignal.timeout(180000),
  });
  const upstreamBody = await upstream.text();
  return json({ providerStatus: upstream.status, providerBody: upstreamBody });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "POST ayaa la rabaa." }, 405);
  if (!projectUrl || !serviceKey) return json({ error: "Gateway configuration is missing." }, 500);

  try {
    const user = await authenticate(req);
    if (!user) return json({ error: "Sign-in ayaa loo baahan yahay." }, 401);
    const payload = (await req.json()) as Row;
    const action = String(payload.action ?? "");

    if (action === "list_keys") {
      requireAdmin(user);
      return json({ keys: await listKeys() });
    }
    if (action === "save_key") {
      requireAdmin(user);
      return json({ key: await saveKey((payload.key ?? {}) as Row) });
    }
    if (action === "delete_key") {
      requireAdmin(user);
      await deleteKey(String(payload.id ?? ""));
      return json({ ok: true });
    }
    if (action === "verify_key") {
      requireAdmin(user);
      return json(await verifyKey(String(payload.id ?? "")));
    }
    if (action === "verify_model") {
      requireAdmin(user);
      return json(await verifyModel(payload));
    }
    if (action === "proxy") return await proxyModel(user, payload);
    return json({ error: "Action aan la aqoon." }, 400);
  } catch (error) {
    const message = error instanceof Error ? error.message : "Request-ku wuu fashilmay.";
    const status = message.includes("Admin permission") ? 403 : 400;
    return json({ error: message }, status);
  }
});
