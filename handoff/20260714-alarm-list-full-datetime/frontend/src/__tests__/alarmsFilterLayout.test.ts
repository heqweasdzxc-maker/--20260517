import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const alarmsPageSource = readFileSync(resolve(__dirname, '../views/pages/AlarmsPage.vue'), 'utf8');
const stylesSource = readFileSync(resolve(__dirname, '../styles.css'), 'utf8');

describe('告警中心筛选栏布局', () => {
  it('关键词输入框缩小到约当前宽度的五分之一', () => {
    expect(alarmsPageSource).toContain('class="alarm-keyword-input"');
    expect(stylesSource).toContain('grid-template-columns: 150px 130px minmax(180px, 224px) auto auto;');
    expect(stylesSource).toContain('.alarm-keyword-input');
    expect(stylesSource).not.toContain('grid-template-columns: 150px 130px minmax(220px, 1fr) auto auto;');
  });
  it('sorts the default time column by persisted timestamps before display-only time text', () => {
    expect(alarmsPageSource).toContain("if (prop === 'time') return alarm.updatedAt || alarm.createdAt || alarm.time");
  });
  it('locks the alarm table default order to newest time first', () => {
    expect(alarmsPageSource).toContain(':default-sort="alarmDefaultSort"');
    expect(alarmsPageSource).toContain("const alarmDefaultSort = { prop: 'time', order: 'descending' } as const");
    expect(alarmsPageSource).toContain("alarmSort.value = order ? { prop: (prop || 'time') as AlarmSortProp, order } : { ...alarmDefaultSort }");
  });
  it('renders a full date and time without changing the persisted timestamp sort', () => {
    expect(alarmsPageSource).toContain("import { formatAlarmDateTime } from '../../utils/alarmDateTime'");
    expect(alarmsPageSource).toContain('prop="time" label="日期时间" min-width="180"');
    expect(alarmsPageSource).toContain('{{ formatAlarmDateTime(row) }}');
    expect(alarmsPageSource).toContain("if (prop === 'time') return alarm.updatedAt || alarm.createdAt || alarm.time");
  });
});
