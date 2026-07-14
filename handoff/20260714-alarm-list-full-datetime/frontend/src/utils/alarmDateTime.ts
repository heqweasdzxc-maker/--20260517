import type { Alarm } from '../types';

const COMPLETE_DATE_TIME = /^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/;
const TIME_ONLY = /^\d{2}:\d{2}:\d{2}$/;
const beijingDateTimeParts = new Intl.DateTimeFormat('zh-CN', {
  timeZone: 'Asia/Shanghai',
  year: 'numeric',
  month: '2-digit',
  day: '2-digit',
  hour12: false,
  hour: '2-digit',
  minute: '2-digit',
  second: '2-digit',
});

export function formatAlarmDateTime(alarm: Alarm) {
  const value = String(alarm.updatedAt || alarm.createdAt || alarm.time || '').trim();
  if (!value || COMPLETE_DATE_TIME.test(value) || TIME_ONLY.test(value)) return value || '--';

  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;

  const parts = Object.fromEntries(
    beijingDateTimeParts
      .formatToParts(date)
      .filter((part) => part.type !== 'literal')
      .map((part) => [part.type, part.value]),
  );
  return `${parts.year}-${parts.month}-${parts.day} ${parts.hour}:${parts.minute}:${parts.second}`;
}
