Exit code: 0
Wall time: 0.1 seconds
Output:
import { onBeforeUnmount, onMounted, ref, type Ref } from 'vue';

const SHANGHAI_TIME_ZONE = 'Asia/Shanghai';
const WEATHER_FALLBACK = '瀹胯縼 路 澶╂皵鏆備笉鍙敤';
const WEATHER_REFRESH_MS = 30 * 60 * 1000;
const WEATHER_TIMEOUT_MS = 8000;
const SUQIAN_WEATHER_URL =
  'https://api.open-meteo.com/v1/forecast?latitude=33.963&longitude=118.2752&current=temperature_2m,weather_code&timezone=Asia%2FShanghai&forecast_days=1';

type WeatherFetcher = (input: RequestInfo | URL, init?: RequestInit) => Promise<Response>;

type CurrentWeatherResponse = {
  current?: {
    temperature_2m?: number;
    weather_code?: number;
  };
};

export type HeaderStatus = {
  dateTimeText: Ref<string>;
  weatherText: Ref<string>;
};

export function formatShanghaiDateTime(date: Date): string {
  const values = Object.fromEntries(
    new Intl.DateTimeFormat('zh-CN', {
      timeZone: SHANGHAI_TIME_ZONE,
      year: 'numeric',
      month: 'numeric',
      day: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
      hourCycle: 'h23',
    })
      .formatToParts(date)
      .map((part) => [part.type, part.value]),
  );
  const weekday = new Intl.DateTimeFormat('zh-CN', {
    timeZone: SHANGHAI_TIME_ZONE,
    weekday: 'long',
  }).format(date);

  return `${values.year}骞?{values.month}鏈?{values.day}鏃?${weekday} ${values.hour}:${values.minute}:${values.second}`;
}

export function weatherCodeLabel(code: number): string {
  if (code === 0) return '鏅?;
  if (code === 1) return '鏅撮棿澶氫簯';
  if (code === 2) return '澶氫簯';
  if (code === 3) return '闃?;
  if (code === 45 || code === 48) return '闆?;
  if (code >= 51 && code <= 57) return '姣涙瘺闆?;
  if (code >= 61 && code <= 67) return '灏忛洦';
  if (code >= 71 && code <= 77) return '灏忛洩';
  if (code >= 80 && code <= 82) return '闃甸洦';
  if (code >= 85 && code <= 86) return '闃甸洩';
  if (code >= 95 && code <= 99) return '闆烽洦';
  return '瀹炴椂';
}

export async function loadSuqianWeather(
  fetcher: WeatherFetcher = globalThis.fetch.bind(globalThis),
): Promise<string> {
  const controller = new AbortController();
  const timeout = globalThis.setTimeout(() => controller.abort(), WEATHER_TIMEOUT_MS);

  try {
    const response = await fetcher(SUQIAN_WEATHER_URL, {
      signal: controller.signal,
      headers: { Accept: 'application/json' },
    });
    if (!response.ok) return WEATHER_FALLBACK;

    const payload = (await response.json()) as CurrentWeatherResponse;
    const temperature = Number(payload.current?.temperature_2m);
    const weatherCode = Number(payload.current?.weather_code);
    if (!Number.isFinite(temperature) || !Number.isFinite(weatherCode)) return WEATHER_FALLBACK;

    return `瀹胯縼 ${weatherCodeLabel(weatherCode)} ${Math.round(temperature)}掳C`;
  } catch {
    return WEATHER_FALLBACK;
  } finally {
    globalThis.clearTimeout(timeout);
  }
}

export function useHeaderStatus(): HeaderStatus {
  const dateTimeText = ref(formatShanghaiDateTime(new Date()));
  const weatherText = ref(WEATHER_FALLBACK);
  let clockTimer: ReturnType<typeof setInterval> | undefined;
  let weatherTimer: ReturnType<typeof setInterval> | undefined;

  const refreshWeather = async () => {
    weatherText.value = await loadSuqianWeather();
  };

  onMounted(() => {
    dateTimeText.value = formatShanghaiDateTime(new Date());
    clockTimer = globalThis.setInterval(() => {
      dateTimeText.value = formatShanghaiDateTime(new Date());
    }, 1000);

    void refreshWeather();
    weatherTimer = globalThis.setInterval(() => void refreshWeather(), WEATHER_REFRESH_MS);
  });

  onBeforeUnmount(() => {
    if (clockTimer) globalThis.clearInterval(clockTimer);
    if (weatherTimer) globalThis.clearInterval(weatherTimer);
  });

  return { dateTimeText, weatherText };
}

