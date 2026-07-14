import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const monitorSource = readFileSync(resolve(__dirname, '../views/pages/MonitorPage.vue'), 'utf8');
const alarmsSource = readFileSync(resolve(__dirname, '../views/pages/AlarmsPage.vue'), 'utf8');
const dialogsSource = readFileSync(resolve(__dirname, '../components/WorkspaceDialogs.vue'), 'utf8');
const workspaceSource = readFileSync(resolve(__dirname, '../composables/useWorkspace.ts'), 'utf8');
const platformSource = readFileSync(resolve(__dirname, '../stores/platform.ts'), 'utf8');
const alarmDialogModelIndex = dialogsSource.indexOf('v-model="alarmDrawer"');
const alarmDialogStart = dialogsSource.lastIndexOf('<el-dialog', alarmDialogModelIndex);
const alarmDialogSource = dialogsSource.slice(alarmDialogStart, dialogsSource.indexOf('</el-dialog>', alarmDialogModelIndex));

describe('simplified alarm handling flow', () => {
  it('keeps realtime anomalies as a read-only alarm feed without direct action buttons', () => {
    expect(monitorSource).toContain('class="realtime-anomaly-row"');
    expect(monitorSource).toContain('class="realtime-anomaly-main"');
    expect(monitorSource).not.toContain('ignoreRealtimeAlarm(alarm)');
    expect(monitorSource).not.toContain('dispatchRealtimeAlarm(alarm)');
    expect(workspaceSource).toContain('async function ignoreRealtimeAlarm');
    expect(workspaceSource).toContain('function dispatchRealtimeAlarm');
    expect(workspaceSource).toContain("platform.reviewAlarm(alarm.id, '忽略')");
    expect(workspaceSource).toContain('platform.dispatchRealtimeAlarmToAlarmCenter(alarm.id)');
    expect(workspaceSource).not.toContain("router.push('/alarms')");
    expect(platformSource).toContain('dispatchRealtimeAlarmToAlarmCenter(id: string)');
    expect(platformSource).toContain('markRealtimeAlarmDispatched(response.data.id)');
  });

  it('keeps the alarm center operation column to review only', () => {
    const start = alarmsSource.indexOf('class-name="alarm-action-cell"');
    const end = alarmsSource.indexOf('</el-table-column>', start);
    const actionColumn = alarmsSource.slice(start, end);

    expect(alarmsSource).not.toContain('@row-click="openAlarmRow"');
    expect(actionColumn).toContain('openAlarm(row.id)');
    expect(actionColumn).not.toContain('reviewAlarmRow(row)');
    expect(actionColumn).not.toContain('confirmActionLabel');
    expect(actionColumn).not.toContain('confirmActionTitle');
  });

  it('uses the required alarm-center message columns including dispatch number', () => {
    const requiredColumns = [
      'label="告警编号"',
      'label="日期时间"',
      'label="派单编号"',
      'label="设备名称"',
      'label="类型"',
      'label="等级"',
      'label="置信度"',
      'label="状态"',
      'label="操作"',
    ];

    let previousIndex = -1;
    for (const column of requiredColumns) {
      const index = alarmsSource.indexOf(column);
      expect(index, `${column} should exist`).toBeGreaterThan(-1);
      expect(index, `${column} should keep the requested order`).toBeGreaterThan(previousIndex);
      previousIndex = index;
    }
  });

  it('shows persisted alarm-time evidence instead of replaying the current live stream', () => {
    expect(alarmDialogSource).toContain('class="alarm-evidence-frame"');
    expect(alarmDialogSource).toContain('selectedAlarmEvidenceBoxes');
    expect(alarmDialogSource).toContain('selectedAlarmEvidenceTime');
    expect(alarmDialogSource).not.toContain(':camera="selectedAlarmReviewCamera"');
    expect(alarmDialogSource).not.toContain(':sentinel="true"');
    expect(workspaceSource).toContain('selectedAlarmEvidenceEvent');
    expect(workspaceSource).toContain('request.boxes');
    expect(workspaceSource).not.toContain('`${alarm.id}-review`');
    expect(alarmDialogSource).toContain('class="detail-grid"');
    expect((alarmDialogSource.match(/<span>/g) || []).length).toBeGreaterThanOrEqual(13);
    expect(alarmDialogSource).toContain("reviewSelectedAlarm('");
    expect(alarmDialogSource).not.toContain('class="alarm-summary"');
    expect(alarmDialogSource).not.toContain('class="drawer-flow"');
  });

  it('keeps the review dialog open until ignore or handled is clicked', () => {
    expect(alarmDialogSource).toContain(':close-on-click-modal="false"');
    expect(alarmDialogSource).toContain(':close-on-press-escape="false"');
    expect(alarmDialogSource).toContain(':show-close="true"');
    expect(workspaceSource).toContain('selectedAlarmSnapshot');
    expect(workspaceSource).toContain('selectedAlarmSnapshot.value = platform.selectedAlarm ? { ...platform.selectedAlarm } : null');
    expect(workspaceSource).toContain('selectedAlarmSnapshot.value = null');
  });

  it('records ignored and handled alarms into the work-order loop for later query', () => {
    expect(platformSource).toContain('createClosedWorkOrderFromAlarm');
    expect(platformSource).toContain('const archived = status ===');
    expect(platformSource).toContain("alarm.status = '");
    expect(platformSource).toContain('reviewResult');
  });

  it('uses alarm center as the message list plus history and closes handled records through work orders', () => {
    const alarmRowsStart = platformSource.indexOf('alarmRows(state): Alarm[]');
    const alarmRowsEnd = platformSource.indexOf('pendingAlarms(state): Alarm[]', alarmRowsStart);
    const alarmRowsSource = platformSource.slice(alarmRowsStart, alarmRowsEnd);

    expect(alarmRowsSource).toContain('return alarmCenterRowsForState(state)');
    expect(platformSource).toContain('function alarmCenterRowsForState');
    expect(platformSource).toContain('function currentRealtimeRowsForState');
    expect(workspaceSource).toContain('async function archiveWorkOrder');
    expect(workspaceSource).toContain('await platform.archiveWorkOrder(order.id)');
  });

  it('keeps archived alarm records out of the current list until history query is used', () => {
    expect(alarmsSource).toContain('alarmQueryActive');
    expect(alarmsSource).toContain('platform.alarmHistoryRows');
    expect(alarmsSource).toContain('platform.alarmRows');
  });
});
