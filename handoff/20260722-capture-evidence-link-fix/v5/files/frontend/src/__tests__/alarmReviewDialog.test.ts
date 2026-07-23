import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const dialogSource = readFileSync(resolve(__dirname, '../components/WorkspaceDialogs.vue'), 'utf8');
const stylesSource = readFileSync(resolve(__dirname, '../styles.css'), 'utf8');

describe('alarm review dialog', () => {
  it('keeps the review dialog explicitly closable', () => {
    expect(dialogSource).toContain('class="alarm-review-dialog"');
    expect(dialogSource).toContain(':show-close="true"');
    expect(dialogSource).toContain(':close-on-click-modal="false"');
  });

  it('renders alarm-time evidence metadata without a live stream player', () => {
    expect(dialogSource).toContain('class="alarm-evidence-frame"');
    expect(dialogSource).toContain('selectedAlarmEvidenceBoxes');
    expect(dialogSource).toContain('selectedAlarmEvidenceTime');
    expect(dialogSource).not.toContain('selectedAlarmReviewCamera');
    expect(dialogSource).not.toContain(':sentinel="true"');
    expect(dialogSource).toContain('class="alarm-review-video-meta"');
    expect(dialogSource).toContain('selectedAlarmDeviceName || selectedAlarm.cameraName');
    expect(dialogSource).toContain('selectedAlarm.type');
    expect(dialogSource).toContain('selectedAggregateEvent.maxConfidence');
    expect(dialogSource).toContain('selectedAlarm.confidence');
    expect(stylesSource).toMatch(/\.alarm-review-video-meta\s*{[^}]*grid-template-columns:\s*repeat\(3,\s*minmax\(0,\s*1fr\)\)/s);
  });

  it('renders persisted alarm-time media and reports missing evidence explicitly', () => {
    expect(dialogSource).toContain("selectedAlarmEvidenceMedia?.type === 'video'");
    expect(dialogSource).toContain("selectedAlarmEvidenceMedia?.type === 'image'");
    expect(dialogSource).toContain('该告警未保存历史截图或片段，禁止使用当前实时视频替代');
    expect(stylesSource).toContain('.alarm-evidence-media');
  });

  it('loads captured alarm evidence through the authenticated evidence endpoint', () => {
    const workspaceSource = readFileSync(resolve(__dirname, '../composables/useWorkspace.ts'), 'utf8');
    expect(workspaceSource).toContain('/api/alarm/alarms/${encodeURIComponent(alarmId)}/evidence');
    expect(workspaceSource).toContain('/api/alarm/alarms/${encodeURIComponent(alarmId)}/evidence/metadata');
    expect(workspaceSource).toContain('capturedAlarmEvidenceUrl.value');
    expect(workspaceSource).toContain('capturedAlarmEvidenceMetadata.value');
    expect(workspaceSource).toContain('Authorization = `Bearer ${platform.authToken}`');
    expect(workspaceSource).toContain('evidenceMatchesSelectedAlarm');
    expect(workspaceSource).toContain('if (!metadataResponse.ok');
    expect(workspaceSource).toContain('if (!evidenceMatchesSelectedAlarm(metadata, alarmId, expectedCameraId))');
    expect(workspaceSource).toContain('证据与当前告警或摄像机不匹配，已拒绝显示');
    expect(workspaceSource.indexOf('/evidence/metadata')).toBeLessThan(workspaceSource.indexOf('/evidence`'));
    expect(workspaceSource).toContain('if (!capturedAlarmEvidenceMetadata.value || !capturedAlarmEvidenceUrl.value) return undefined;');
    expect(workspaceSource).toContain('const boxes = Array.isArray(persistedBoxes) ? persistedBoxes : [];');
    expect(workspaceSource).not.toContain('{ url: alarm.snapshot');
  });

  it('preserves the deployed evidence loading and error states while enforcing camera binding', () => {
    const workspaceSource = readFileSync(resolve(__dirname, '../composables/useWorkspace.ts'), 'utf8');
    expect(workspaceSource).toContain('const capturedAlarmEvidenceLoading = ref(false);');
    expect(workspaceSource).toContain("const capturedAlarmEvidenceError = ref('');");
    expect(workspaceSource).toContain("cache: 'no-store' as const");
    expect(workspaceSource).toContain('capturedAlarmEvidenceLoading.value = Boolean(alarmId);');
    expect(workspaceSource).toContain('capturedAlarmEvidenceError.value =');
    expect(workspaceSource).toContain('evidenceMatchesSelectedAlarm(metadata, alarmId, expectedCameraId)');
  });

  it('renders the alarm detail fields in three columns', () => {
    expect(dialogSource).toContain('class="alarm-review-detail-grid"');
    expect(dialogSource.match(/class="alarm-review-detail-item"/g)).toHaveLength(13);
    expect(dialogSource).toContain('<b>首次发生</b>');
    expect(dialogSource).toContain('<b>最近报警</b>');
    expect(dialogSource).toContain('<b>归集统计</b>');
    expect(dialogSource).toContain('selectedAggregateEvent');
    expect(stylesSource).toMatch(/\.alarm-review-detail-grid\s*{[^}]*grid-template-columns:\s*repeat\(3,\s*minmax\(0,\s*1fr\)\)/s);
  });

  it('uses ignore/handled actions from the review dialog instead of the old false-positive wording', () => {
    expect(dialogSource).toContain("reviewSelectedAlarm('忽略')");
    expect(dialogSource).toContain("reviewSelectedAlarm('已处理')");
    expect(dialogSource).not.toContain('标记误报');
  });
});
