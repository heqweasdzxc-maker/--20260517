Exit code: 0
Wall time: 0.1 seconds
Output:
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const sourceRoot = resolve(process.cwd(), 'src');
const appShellSource = readFileSync(resolve(sourceRoot, 'components/AppShell.vue'), 'utf-8');
const kpiCardSource = readFileSync(resolve(sourceRoot, 'components/KpiCard.vue'), 'utf-8');
const statusBadgeSource = readFileSync(resolve(sourceRoot, 'components/StatusBadge.vue'), 'utf-8');
const cssSource = readFileSync(resolve(sourceRoot, 'styles.css'), 'utf-8');

describe('command center UI baseline', () => {
  it('gives the shell a stable route title and subtitle structure', () => {
    expect(appShellSource).toContain('command-shell');
    expect(appShellSource).toContain('AI瑙嗛鍒嗘瀽绯荤粺');
    expect(appShellSource).toContain('娲嬫渤鑲′唤娉楅槼鍩哄湴瀹夌幆閮?);
    expect(appShellSource).toContain('topbar-title');
    expect(appShellSource).not.toContain('route-title__main');
    expect(appShellSource).not.toContain('route-title__sub');
    expect(appShellSource).not.toContain('routeSubtitle');
  });

  it('centers the tenant title and replaces the top notification with time and weather', () => {
    expect(appShellSource).toContain('useHeaderStatus');
    expect(appShellSource).toContain('topbar-clock');
    expect(appShellSource).toContain('topbar-weather');
    expect(appShellSource).toContain('{{ dateTimeText }}');
    expect(appShellSource).toContain('{{ weatherText }}');
    expect(appShellSource).not.toContain('title="绯荤粺閫氱煡"');
    expect(appShellSource).not.toContain("goTo('/notify')");
    expect(cssSource).toContain('--shell-sidebar-width: 246px');
    expect(cssSource).toContain('left: calc(50vw - var(--shell-sidebar-width))');
  });

  it('renders KPI hints as first-class operational metadata', () => {
    expect(kpiCardSource).toContain('kpi-copy__hint');
    expect(kpiCardSource).toContain('{{ hint }}');
  });

  it('exposes status tone hooks for consistent theme styling', () => {
    expect(statusBadgeSource).toContain(':data-tone="tone ||');
    expect(statusBadgeSource).toContain('status-badge__dot');
  });

  it('defines command-center table, button and overflow rules globally', () => {
    expect(cssSource).toContain('--command-surface');
    expect(cssSource).toContain('--table-row-height');
    expect(cssSource).toContain('.command-shell .el-table');
    expect(cssSource).toContain('.command-shell .el-table .cell');
    expect(cssSource).toContain('.command-shell .el-button');
    expect(cssSource).toContain('.command-shell .panel-title');
  });
});

