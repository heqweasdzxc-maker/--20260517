import { describe, expect, it } from 'vitest';
import type { Alarm } from '../types';
import { formatAlarmDateTime } from '../utils/alarmDateTime';

function alarmWithTime(values: Partial<Alarm>) {
  return {
    time: '',
    ...values,
  } as Alarm;
}

describe('formatAlarmDateTime', () => {
  it('formats persisted ISO timestamps in Beijing time', () => {
    expect(formatAlarmDateTime(alarmWithTime({ createdAt: '2026-07-14T08:24:04.000Z', time: '16:24:04' })))
      .toBe('2026-07-14 16:24:04');
  });

  it('prefers updatedAt and preserves an existing complete datetime', () => {
    expect(formatAlarmDateTime(alarmWithTime({
      updatedAt: '2026-07-13 23:59:59',
      createdAt: '2026-07-12T08:00:00.000Z',
      time: '23:59:59',
    }))).toBe('2026-07-13 23:59:59');
  });

  it('keeps a legacy time-only value when no date is available', () => {
    expect(formatAlarmDateTime(alarmWithTime({ time: '08:42:20' }))).toBe('08:42:20');
  });
});
