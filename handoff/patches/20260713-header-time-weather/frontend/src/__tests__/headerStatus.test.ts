Exit code: 0
Wall time: 0.1 seconds
Output:
import { describe, expect, it, vi } from 'vitest';
import {
  formatShanghaiDateTime,
  loadSuqianWeather,
  weatherCodeLabel,
} from '../composables/useHeaderStatus';

describe('header status', () => {
  it('formats a stable Asia/Shanghai date and time', () => {
    expect(formatShanghaiDateTime(new Date('2026-07-13T05:40:01.000Z'))).toBe(
      '2026骞?鏈?3鏃?鏄熸湡涓€ 13:40:01',
    );
  });

  it.each([
    [0, '鏅?],
    [1, '鏅撮棿澶氫簯'],
    [2, '澶氫簯'],
    [3, '闃?],
    [45, '闆?],
    [51, '姣涙瘺闆?],
    [61, '灏忛洦'],
    [71, '灏忛洩'],
    [80, '闃甸洦'],
    [95, '闆烽洦'],
    [999, '瀹炴椂'],
  ])('maps WMO weather code %s to %s', (code, label) => {
    expect(weatherCodeLabel(code)).toBe(label);
  });

  it('loads current Suqian weather directly from the browser', async () => {
    const fetcher = vi.fn(async (_input: RequestInfo | URL, _init?: RequestInit) =>
      new Response(
        JSON.stringify({ current: { temperature_2m: 27.6, weather_code: 0 } }),
        { status: 200, headers: { 'Content-Type': 'application/json' } },
      ),
    );

    await expect(loadSuqianWeather(fetcher)).resolves.toBe('瀹胯縼 鏅?28掳C');
    expect(fetcher).toHaveBeenCalledOnce();
    expect(String(fetcher.mock.calls[0]?.[0])).toContain('api.open-meteo.com/v1/forecast');
  });

  it.each([
    vi.fn(async () => new Response('service unavailable', { status: 503 })),
    vi.fn(async () => {
      throw new TypeError('offline');
    }),
  ])('falls back without affecting the application', async (fetcher) => {
    await expect(loadSuqianWeather(fetcher)).resolves.toBe('瀹胯縼 路 澶╂皵鏆備笉鍙敤');
  });
});

