import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
};

const cacheKey = "bjfu";
const defaultCity = "110108";
const cacheMaxAgeMs = 6 * 60 * 60 * 1000;
const amapWeatherURL = "https://restapi.amap.com/v3/weather/weatherInfo";
const openMeteoWeatherURL = "https://api.open-meteo.com/v1/forecast";

type CampusWeatherResponse = {
  temperature: number;
  condition_key: string;
  observed_at: string;
  source: string;
  is_stale: boolean;
};

type WeatherCacheRecord = {
  cache_key: string;
  temperature: number;
  condition_key: string;
  observed_at: string;
  source: string;
  updated_at: string;
};

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (request.method !== "GET") {
    return json({ error: "Method not allowed." }, 405);
  }

  const client = makeSupabaseClient();
  if (!client) {
    return json({ error: "Missing Supabase environment variables." }, 500);
  }

  try {
    const weather = await fetchCurrentWeather();
    await saveCache(client, weather);
    return json(weather);
  } catch (error) {
    const cached = await fetchFreshCache(client);
    if (cached) {
      console.error("campus-weather: remote weather failed, returning cached weather", errorMessage(error));
      return json({
        temperature: cached.temperature,
        condition_key: cached.condition_key,
        observed_at: cached.observed_at,
        source: cached.source,
        is_stale: true,
      });
    }

    console.error("campus-weather: no weather source available", errorMessage(error));
    return json({ error: "Campus weather unavailable." }, 503);
  }
});

function makeSupabaseClient() {
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

  if (!supabaseUrl || !serviceRoleKey) {
    return null;
  }

  return createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false },
  });
}

async function fetchCurrentWeather(): Promise<CampusWeatherResponse> {
  let openMeteoError: unknown;
  try {
    return await fetchFromOpenMeteo();
  } catch (error) {
    openMeteoError = error;
    console.error("campus-weather: Open-Meteo failed, falling back to AMap", errorMessage(error));
  }

  try {
    return await fetchFromAmap();
  } catch (error) {
    throw new Error(
      `No remote weather source available. open_meteo=${errorMessage(openMeteoError)} amap=${errorMessage(error)}`,
    );
  }
}

async function fetchFromOpenMeteo(): Promise<CampusWeatherResponse> {
  const url = new URL(openMeteoWeatherURL);
  url.searchParams.set("latitude", "40.006");
  url.searchParams.set("longitude", "116.352");
  url.searchParams.set("current", "temperature_2m,weather_code");
  url.searchParams.set("timezone", "Asia/Shanghai");

  const response = await fetch(url, {
    headers: { Accept: "application/json" },
    signal: AbortSignal.timeout(8000),
  });

  if (!response.ok) {
    throw new Error(`Open-Meteo request failed with status ${response.status}.`);
  }

  const payload = await response.json();
  const current = payload.current;
  const temperature = parseTemperature(current?.temperature_2m);
  const conditionKey = openMeteoConditionKey(Number.parseInt(String(current?.weather_code ?? ""), 10));

  if (temperature == null || !conditionKey) {
    throw new Error("Open-Meteo returned no usable current weather.");
  }

  return {
    temperature,
    condition_key: conditionKey,
    observed_at: parseObservedAt(current?.time),
    source: "open-meteo",
    is_stale: false,
  };
}

async function fetchFromAmap(): Promise<CampusWeatherResponse> {
  const key = Deno.env.get("AMAP_WEATHER_KEY")?.trim();
  if (!key) {
    throw new Error("Missing AMAP_WEATHER_KEY secret.");
  }

  const city = Deno.env.get("AMAP_WEATHER_CITY")?.trim() || defaultCity;
  let liveError: unknown;
  try {
    const liveWeather = await fetchAmapLiveWeather(key, city);
    if (liveWeather) {
      return liveWeather;
    }
  } catch (error) {
    liveError = error;
    console.error("campus-weather: AMap live weather failed", errorMessage(error));
  }

  try {
    const forecastWeather = await fetchAmapForecastWeather(key, city);
    if (forecastWeather) {
      return forecastWeather;
    }
  } catch (error) {
    console.error("campus-weather: AMap forecast weather failed", errorMessage(error));
  }

  throw new Error(`AMap returned no usable weather.${liveError ? ` live=${errorMessage(liveError)}` : ""}`);
}

async function fetchAmapLiveWeather(key: string, city: string): Promise<CampusWeatherResponse | null> {
  const payload = await fetchAmapPayload(key, city, "base");
  const live = firstArrayItem(payload.lives);
  const temperature = parseTemperature(live?.temperature);
  const conditionKey = normalizeCondition(live?.weather);

  if (temperature == null || !conditionKey) {
    return null;
  }

  return {
    temperature,
    condition_key: conditionKey,
    observed_at: parseObservedAt(live?.reporttime),
    source: "amap-live",
    is_stale: false,
  };
}

async function fetchAmapForecastWeather(key: string, city: string): Promise<CampusWeatherResponse | null> {
  const payload = await fetchAmapPayload(key, city, "all");
  const forecast = firstArrayItem(payload.forecasts);
  const cast = firstArrayItem(forecast?.casts);
  const dayTemperature = parseTemperature(cast?.daytemp);
  const nightTemperature = parseTemperature(cast?.nighttemp);
  const conditionKey = normalizeCondition(cast?.dayweather) ?? normalizeCondition(cast?.nightweather);

  if ((dayTemperature == null && nightTemperature == null) || !conditionKey) {
    return null;
  }

  const temperatures = [dayTemperature, nightTemperature].filter((value): value is number => value != null);
  const temperature = temperatures.reduce((sum, value) => sum + value, 0) / temperatures.length;

  return {
    temperature,
    condition_key: conditionKey,
    observed_at: parseObservedAt(forecast?.reporttime ?? cast?.date),
    source: "amap-forecast",
    is_stale: false,
  };
}

async function fetchAmapPayload(key: string, city: string, extensions: "base" | "all"): Promise<Record<string, unknown>> {
  const url = new URL(amapWeatherURL);
  url.searchParams.set("key", key);
  url.searchParams.set("city", city);
  url.searchParams.set("extensions", extensions);
  url.searchParams.set("output", "json");

  const response = await fetch(url, {
    headers: { Accept: "application/json" },
    signal: AbortSignal.timeout(8000),
  });

  if (!response.ok) {
    throw new Error(`AMap ${extensions} request failed with status ${response.status}.`);
  }

  const payload = await response.json();
  if (payload.status !== "1") {
    throw new Error(`AMap ${extensions} rejected request: ${payload.info ?? "unknown error"}.`);
  }

  return payload;
}

async function saveCache(client: ReturnType<typeof createClient>, weather: CampusWeatherResponse) {
  const { error } = await client
    .from("campus_weather_cache")
    .upsert({
      cache_key: cacheKey,
      temperature: weather.temperature,
      condition_key: weather.condition_key,
      observed_at: weather.observed_at,
      source: weather.source,
      updated_at: new Date().toISOString(),
    }, {
      onConflict: "cache_key",
    });

  if (error) {
    console.error("campus-weather: cache upsert failed", error.message);
  }
}

async function fetchFreshCache(client: ReturnType<typeof createClient>): Promise<WeatherCacheRecord | null> {
  const { data, error } = await client
    .from("campus_weather_cache")
    .select("*")
    .eq("cache_key", cacheKey)
    .maybeSingle();

  if (error) {
    console.error("campus-weather: cache read failed", error.message);
    return null;
  }

  if (!data) {
    return null;
  }

  const updatedAt = Date.parse(data.updated_at);
  if (!Number.isFinite(updatedAt) || Date.now() - updatedAt > cacheMaxAgeMs) {
    return null;
  }

  return data as WeatherCacheRecord;
}

function normalizeCondition(value: unknown): string | null {
  const text = String(value ?? "").trim();
  if (!text || text === "NULL") {
    return null;
  }

  if (text.includes("雷")) {
    return "雷雨";
  }
  if (text.includes("雪") || text.includes("冰雹")) {
    return "雪";
  }
  if (text.includes("雨")) {
    return text.includes("毛毛") || text.includes("小雨") ? "毛毛雨" : "雨";
  }
  if (text.includes("雾") || text.includes("霾") || text.includes("浮尘") || text.includes("扬沙") || text.includes("沙尘")) {
    return "雾";
  }
  if (text.includes("阴")) {
    return "阴";
  }
  if (text.includes("云")) {
    return "多云";
  }
  if (text.includes("晴")) {
    return "晴";
  }

  return "天气";
}

function openMeteoConditionKey(code: number): string | null {
  if (!Number.isFinite(code)) {
    return null;
  }

  switch (code) {
    case 0:
      return "晴";
    case 1:
    case 2:
      return "多云";
    case 3:
      return "阴";
    case 45:
    case 48:
      return "雾";
    case 51:
    case 53:
    case 55:
    case 56:
    case 57:
      return "毛毛雨";
    case 61:
    case 63:
    case 65:
    case 66:
    case 67:
    case 80:
    case 81:
    case 82:
      return "雨";
    case 71:
    case 73:
    case 75:
    case 77:
    case 85:
    case 86:
      return "雪";
    case 95:
    case 96:
    case 99:
      return "雷雨";
    default:
      return "天气";
  }
}

function parseTemperature(value: unknown): number | null {
  const parsed = Number.parseFloat(String(value ?? "").trim());
  return Number.isFinite(parsed) ? parsed : null;
}

function parseObservedAt(value: unknown): string {
  const text = String(value ?? "").trim();
  if (!text) {
    return new Date().toISOString();
  }

  const normalized = text.includes("T") ? text : text.replace(" ", "T") + "+08:00";
  const parsed = Date.parse(normalized);
  return Number.isFinite(parsed) ? new Date(parsed).toISOString() : new Date().toISOString();
}

function firstArrayItem(value: unknown): Record<string, unknown> | null {
  return Array.isArray(value) && value.length > 0 ? value[0] : null;
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

function json(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {
      "Content-Type": "application/json",
      ...corsHeaders,
    },
  });
}
