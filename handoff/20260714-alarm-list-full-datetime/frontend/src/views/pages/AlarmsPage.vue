<script setup lang="ts">
import { computed, ref, watch } from 'vue';
import { Activity, AlertTriangle, ArrowRight, CheckCircle2, CircleDot, Clock3, CloudUpload, Download, FileCheck2, Pause, Play, Plus, RefreshCw, RotateCcw, ScanLine, Send, ShieldCheck, SlidersHorizontal, TimerReset, Workflow } from '@lucide/vue';
import KpiCard from '../../components/KpiCard.vue';
import RiskTrendChart from '../../components/RiskTrendChart.vue';
import StatusBadge from '../../components/StatusBadge.vue';
import StreamPlayer from '../../components/StreamPlayer.vue';
import TencentMapPanel from '../../components/TencentMapPanel.vue';
import VideoTile from '../../components/VideoTile.vue';
import { useWorkspace } from '../../composables/useWorkspace';
import type { Alarm } from '../../types';
import { formatAlarmDateTime } from '../../utils/alarmDateTime';

const {
  platform,
  alarmDrawer,
  operationDialog,
  operationAction,
  deviceDialog,
  deviceDialogMode,
  deviceSubmitting,
  cameraPreviewDialog,
  cameraPreviewMode,
  cameraPreviewId,
  cameraTypeOptions,
  protocolOptions,
  inferenceNodeOptions,
  deviceForm,
  page,
  pageTitle,
  selectedAlarm,
  selectedCamera,
  mainTrend,
  playbackPageSize,
  playbackPage,
  playbackPlaying,
  playbackProgress,
  playbackNotice,
  templateCoverage,
  algorithmAverageLatency,
  eventKpis,
  eventTypeStats,
  eventStatusStats,
  pageRecordCount,
  workOrderStats,
  latestEvidenceVerification,
  deviceRows,
  playbackEvents,
  playbackTotalPages,
  pagedPlaybackEvents,
  playbackCurrentTime,
  selectedAlarmWorkOrder,
  selectedAlarmCamera,
  selectedAlarmDeviceName,
  selectedAlarmUavTask,
  selectedAlarmEvidence,
  previewCamera,
  cameraPreviewTitle,
  cameraNameById,
  openAlarm,
  openPlaybackAlarm,
  alarmDeviceName,
  alarmReviewTitle,
  deviceNameById,
  workOrderDisplayTitle,
  uavTaskDisplayTitle,
  evidenceBundleDisplayName,
  openOperation,
  handleOperationDone,
  openCreateDevice,
  openEditDevice,
  resetDeviceForm,
  submitDeviceForm,
  deleteDevice,
  devicePayloadFromForm,
  parseCoordinate,
  cameraTypeOf,
  cameraCoordinate,
  streamUrlOf,
  channelNumber,
  reviewSelectedAlarm,
  findCameraAlarm,
  openCameraAlarm,
  openCameraMap,
  openCameraPreview,
  handleCameraAction,
  nextWorkOrderAction,
  advanceWorkOrder,
  remindWorkOrder,
  createEvidenceBundle,
  verifyEvidenceBundle,
  downloadEvidenceBundle,
  createImportJob,
  reanalyzeImportJob,
  convertImportJobToAlarm,
  deleteImportJob,
  createStoragePolicy,
  protectStoragePolicy,
  createReportTask,
  downloadReport,
  createUserAccount,
  toggleUserStatus,
  saveRolePermissions,
  searchAuditLogs,
  exportAuditLogs,
  verifyOps,
  opsTone,
  resetPlayback,
  startPlayback,
  pausePlayback,
  locateSelectedAlarm,
  importStatusTone,
  goDiagnostics,
  handleMapCameraSelect,
  stepTone,
  ptsToProgress,
  progressToTime,
  timecodeToSeconds,
  severityTone,
  statusTone,
  progressOfWorkOrder,
  isSlaRisk,
} = useWorkspace();

type AlarmSortProp = 'id' | 'time' | 'dispatchId' | 'device' | 'type' | 'severity' | 'confidence' | 'status';
type AlarmSortOrder = 'ascending' | 'descending' | null;

const ALARM_PAGE_SIZE = 20;
const severityRank = new Map([
  ['提示', 1],
  ['一般', 2],
  ['严重', 3],
  ['紧急', 4],
]);
const statusRank = new Map([
  ['误报', 0],
  ['待研判', 1],
  ['已确认', 2],
  ['已派单', 3],
  ['已归档', 4],
]);
const alarmDefaultSort = { prop: 'time', order: 'descending' } as const;
const alarmPage = ref(1);
const alarmSort = ref<{ prop: AlarmSortProp; order: AlarmSortOrder }>({ ...alarmDefaultSort });
const alarmStatusFilter = ref('');
const alarmSeverityFilter = ref('');
const alarmKeyword = ref('');
const alarmStatusOptions = ['待研判', '已确认', '已派单', '已归档', '忽略', '误报'];
const alarmSeverityOptions = ['提示', '一般', '严重', '紧急'];
const alarmQueryActive = computed(() => Boolean(alarmStatusFilter.value || alarmSeverityFilter.value || alarmKeyword.value.trim()));
const filteredAlarms = computed(() => {
  const keyword = alarmKeyword.value.trim().toLowerCase();
  const sourceRows = alarmQueryActive.value ? platform.alarmHistoryRows : platform.alarmRows;
  return sourceRows.filter((alarm) => {
    const statusMatched =
      !alarmStatusFilter.value ||
      (alarmStatusFilter.value === '忽略' ? alarm.reviewResult === '忽略' : alarm.status === alarmStatusFilter.value);
    const severityMatched = !alarmSeverityFilter.value || alarm.severity === alarmSeverityFilter.value;
    const keywordMatched =
      !keyword ||
      [alarm.id, alarmDeviceName(alarm), alarm.type, alarm.cameraId, alarm.owner, alarm.reviewResult || '', alarm.archiveReason || '']
        .some((value) => String(value || '').toLowerCase().includes(keyword));
    return statusMatched && severityMatched && keywordMatched;
  });
});
const alarmTotal = computed(() => filteredAlarms.value.length);
const alarmTotalPages = computed(() => Math.max(1, Math.ceil(alarmTotal.value / ALARM_PAGE_SIZE)));
const sortedAlarms = computed(() => {
  const rows = [...filteredAlarms.value];
  const { prop, order } = alarmSort.value;
  if (!order) return rows;

  const direction = order === 'ascending' ? 1 : -1;
  return rows.sort((a, b) => {
    const primary = compareAlarmValue(alarmSortValue(a, prop), alarmSortValue(b, prop));
    if (primary !== 0) return primary * direction;
    return b.time.localeCompare(a.time, 'zh-CN') || a.id.localeCompare(b.id, 'zh-CN');
  });
});
const pagedAlarms = computed(() => {
  const start = (alarmPage.value - 1) * ALARM_PAGE_SIZE;
  return sortedAlarms.value.slice(start, start + ALARM_PAGE_SIZE);
});

function alarmSortValue(alarm: Alarm, prop: AlarmSortProp) {
  if (prop === 'time') return alarm.updatedAt || alarm.createdAt || alarm.time;
  if (prop === 'device') return alarmDeviceName(alarm);
  if (prop === 'dispatchId') return alarm.dispatchId || '';
  if (prop === 'severity') return severityRank.get(alarm.severity) ?? 0;
  if (prop === 'confidence') return alarm.confidence;
  if (prop === 'status') return statusRank.get(alarm.status) ?? 0;
  return alarm[prop];
}

function compareAlarmValue(a: string | number, b: string | number) {
  if (typeof a === 'number' && typeof b === 'number') return a - b;
  return String(a).localeCompare(String(b), 'zh-CN', { numeric: true });
}

function handleAlarmSortChange({ prop, order }: { prop: string; order: AlarmSortOrder }) {
  alarmSort.value = order ? { prop: (prop || 'time') as AlarmSortProp, order } : { ...alarmDefaultSort };
  alarmPage.value = 1;
}

function resetAlarmFilters() {
  alarmStatusFilter.value = '';
  alarmSeverityFilter.value = '';
  alarmKeyword.value = '';
  alarmPage.value = 1;
}

watch(alarmTotalPages, (totalPages) => {
  if (alarmPage.value > totalPages) alarmPage.value = totalPages;
});

watch([alarmStatusFilter, alarmSeverityFilter, alarmKeyword], () => {
  alarmPage.value = 1;
});
</script>

<template>
  <section class="panel alarm-list-panel" :data-page-size="ALARM_PAGE_SIZE" :data-total="alarmTotal">
    <div class="alarm-history-filters" aria-label="告警历史查询">
      <el-select v-model="alarmStatusFilter" clearable size="small" placeholder="状态 / 历史归档">
        <el-option v-for="status in alarmStatusOptions" :key="status" :label="status" :value="status" />
      </el-select>
      <el-select v-model="alarmSeverityFilter" clearable size="small" placeholder="告警等级">
        <el-option v-for="severity in alarmSeverityOptions" :key="severity" :label="severity" :value="severity" />
      </el-select>
      <el-input class="alarm-keyword-input" v-model="alarmKeyword" clearable size="small" placeholder="告警编号 / 设备 / 类型 / 处置人" />
      <el-button size="small" @click="resetAlarmFilters"><RefreshCw :size="15" />重置</el-button>
      <span>历史查询 {{ alarmTotal }} 条</span>
    </div>
    <el-table class="alarm-table" :data="pagedAlarms" stripe border table-layout="fixed" :default-sort="alarmDefaultSort" @sort-change="handleAlarmSortChange">
      <el-table-column prop="id" label="告警编号" min-width="170" sortable="custom" resizable class-name="alarm-id-cell" />
      <el-table-column prop="time" label="日期时间" min-width="180" sortable="custom" resizable class-name="alarm-nowrap-cell">
        <template #default="{ row }">{{ formatAlarmDateTime(row) }}</template>
      </el-table-column>
      <el-table-column prop="dispatchId" label="派单编号" min-width="150" sortable="custom" resizable class-name="alarm-nowrap-cell">
        <template #default="{ row }">{{ row.dispatchId || '--' }}</template>
      </el-table-column>
      <el-table-column prop="device" label="设备名称" min-width="170" sortable="custom" resizable class-name="alarm-nowrap-cell">
        <template #default="{ row }">{{ alarmDeviceName(row) }}</template>
      </el-table-column>
      <el-table-column prop="type" label="类型" min-width="140" sortable="custom" resizable class-name="alarm-type-cell" />
      <el-table-column prop="severity" label="等级" min-width="112" sortable="custom" resizable class-name="alarm-badge-cell">
        <template #default="{ row }"><StatusBadge :label="row.severity" :tone="severityTone(row.severity)" /></template>
      </el-table-column>
      <el-table-column prop="confidence" label="置信度" min-width="120" sortable="custom" resizable class-name="alarm-nowrap-cell">
        <template #default="{ row }">{{ row.confidence }}%</template>
      </el-table-column>
      <el-table-column prop="status" label="状态" min-width="126" sortable="custom" resizable class-name="alarm-badge-cell">
        <template #default="{ row }"><StatusBadge :label="row.status" :tone="statusTone(row.status)" /></template>
      </el-table-column>
      <el-table-column label="操作" min-width="180" resizable class-name="alarm-action-cell">
        <template #default="{ row }">
          <div class="alarm-actions">
            <el-button size="small" type="primary" plain @click.stop="openAlarm(row.id)">研判</el-button>
          </div>
        </template>
      </el-table-column>
    </el-table>
    <div v-if="alarmTotal > ALARM_PAGE_SIZE" class="alarm-pager">
      <span>每页 {{ ALARM_PAGE_SIZE }} 条，共 {{ alarmTotal }} 条</span>
      <el-pagination
        v-model:current-page="alarmPage"
        background
        small
        layout="prev, pager, next"
        :page-size="ALARM_PAGE_SIZE"
        :total="alarmTotal"
      />
    </div>
  </section>
</template>
