<script setup lang="ts">
import OperationDialog from './OperationDialog.vue';
import StatusBadge from './StatusBadge.vue';
import StreamPlayer from './StreamPlayer.vue';
import { useWorkspace } from '../composables/useWorkspace';

const {
  platform,
  alarmDrawer,
  operationDialog,
  operationAction,
  deviceDialog,
  deviceDialogMode,
  deviceSubmitting,
  uavAssetDialog,
  uavAssetDialogMode,
  uavAssetSubmitting,
  cameraPreviewDialog,
  cameraPreviewMode,
  cameraPreviewId,
  cameraTypeOptions,
  protocolOptions,
  inferenceNodeOptions,
  uavAssetStatusOptions,
  uavAssetModelOptions,
  deviceForm,
  uavAssetForm,
  page,
  pageTitle,
  selectedAlarm,
  selectedAggregateEvent,
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
  selectedAlarmEvidenceEvent,
  selectedAlarmEvidenceMedia,
  selectedAlarmEvidenceStatusText,
  selectedAlarmEvidenceBoxes,
  selectedAlarmEvidenceTime,
  selectedAlarmEvidenceSource,
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
  submitUavAssetForm,
  devicePayloadFromForm,
  parseCoordinate,
  cameraTypeOf,
  cameraCoordinate,
  streamUrlOf,
  evidenceBoxStyle,
  uavCoordinate,
  channelNumber,
  reviewSelectedAlarm,
  findCameraAlarm,
  openCameraAlarm,
  openCameraMap,
  openCameraPreview,
  handleCameraAction,
  openAlarmRow,
  reviewAlarmRow,
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
  formatEventDateTime,
  progressOfWorkOrder,
  isSlaRisk,
} = useWorkspace();
</script>

<template>
  <div class="workspace-dialogs">
  <OperationDialog
    v-model="operationDialog"
    :action="operationAction"
    :page-key="page"
    :page-title="pageTitle"
    :record-count="pageRecordCount"
    @done="handleOperationDone"
  />

  <el-dialog v-model="deviceDialog" class="device-dialog" width="680px" :title="deviceDialogMode === 'edit' ? '修改设备' : '新增设备'" destroy-on-close>
    <el-form label-position="top" class="device-form-grid">
      <el-form-item label="设备名称" class="field-wide">
        <el-input v-model="deviceForm.name" placeholder="例如：排水口-10 摄像机" />
      </el-form-item>
      <el-form-item label="摄像机类型">
        <el-select v-model="deviceForm.cameraType" style="width: 100%">
          <el-option v-for="item in cameraTypeOptions" :key="item" :label="item" :value="item" />
        </el-select>
      </el-form-item>
      <el-form-item label="接入协议">
        <el-select v-model="deviceForm.protocol" style="width: 100%">
          <el-option v-for="item in protocolOptions" :key="item" :label="item" :value="item" />
        </el-select>
      </el-form-item>
      <el-form-item label="经度">
        <el-input v-model="deviceForm.longitude" placeholder="例如：121.473700" />
      </el-form-item>
      <el-form-item label="纬度">
        <el-input v-model="deviceForm.latitude" placeholder="例如：31.230400" />
      </el-form-item>
      <el-form-item label="IP 地址">
        <el-input v-model="deviceForm.ip" placeholder="例如：10.20.1.20" />
      </el-form-item>
      <el-form-item label="推理节点">
        <el-select v-model="deviceForm.node" style="width: 100%">
          <el-option v-for="item in inferenceNodeOptions" :key="item" :label="item" :value="item" />
        </el-select>
      </el-form-item>
      <el-form-item label="视频推流地址（可选）" class="field-wide">
        <el-input v-model="deviceForm.streamUrl" placeholder="GB28181 可留空；RTSP 例：rtsp://10.20.1.20/stream1" />
        <small>IP 用于设备网络诊断；推流地址用于媒体接入，二者不是重复字段。</small>
      </el-form-item>
    </el-form>
    <template #footer>
      <el-button :disabled="deviceSubmitting" @click="deviceDialog = false">取消</el-button>
      <el-button type="primary" :loading="deviceSubmitting" @click="submitDeviceForm">保存设备</el-button>
    </template>
  </el-dialog>

  <el-dialog v-model="uavAssetDialog" class="device-dialog uav-asset-dialog" width="760px" :title="uavAssetDialogMode === 'edit' ? '修改无人机资产' : '新增无人机资产'" destroy-on-close>
    <el-form label-position="top" class="device-form-grid">
      <el-form-item label="资产名称" class="field-wide">
        <el-input v-model="uavAssetForm.name" placeholder="例如：大疆机场-M3TD 东岸巡检组" />
      </el-form-item>
      <el-form-item label="产品形态">
        <el-select v-model="uavAssetForm.assetType" style="width: 100%">
          <el-option label="无人机/机巢" value="无人机/机巢" />
          <el-option label="无人机" value="无人机" />
        </el-select>
      </el-form-item>
      <el-form-item label="厂商">
        <el-select v-model="uavAssetForm.vendor" style="width: 100%">
          <el-option label="DJI 大疆" value="DJI" />
          <el-option label="其他" value="Other" />
        </el-select>
      </el-form-item>
      <el-form-item label="产品型号" class="field-wide">
        <el-select v-model="uavAssetForm.model" filterable allow-create default-first-option style="width: 100%">
          <el-option v-for="item in uavAssetModelOptions" :key="item" :label="item" :value="item" />
        </el-select>
      </el-form-item>
      <el-form-item label="机巢名称">
        <el-input v-model="uavAssetForm.dockName" placeholder="例如：东岸机巢" />
      </el-form-item>
      <el-form-item label="状态">
        <el-select v-model="uavAssetForm.status" style="width: 100%">
          <el-option v-for="item in uavAssetStatusOptions" :key="item" :label="item" :value="item" />
        </el-select>
      </el-form-item>
      <el-form-item label="控制模式">
        <el-select v-model="uavAssetForm.mode" style="width: 100%">
          <el-option label="自动确认" value="auto" />
          <el-option label="手动操控" value="manual" />
        </el-select>
      </el-form-item>
      <el-form-item label="机巢 SN">
        <el-input v-model="uavAssetForm.dockSn" placeholder="DJI-DOCK-..." />
      </el-form-item>
      <el-form-item label="无人机 SN">
        <el-input v-model="uavAssetForm.droneSn" placeholder="DJI-M3TD-..." />
      </el-form-item>
      <el-form-item label="经度">
        <el-input v-model="uavAssetForm.longitude" placeholder="例如：121.473700" />
      </el-form-item>
      <el-form-item label="纬度">
        <el-input v-model="uavAssetForm.latitude" placeholder="例如：31.230400" />
      </el-form-item>
      <el-form-item label="电量">
        <el-input-number v-model="uavAssetForm.battery" :min="0" :max="100" style="width: 100%" />
      </el-form-item>
      <el-form-item label="信号">
        <el-input-number v-model="uavAssetForm.signal" :min="0" :max="100" style="width: 100%" />
      </el-form-item>
      <el-form-item label="高度">
        <el-input-number v-model="uavAssetForm.altitude" :min="0" :max="500" style="width: 100%" />
      </el-form-item>
      <el-form-item label="速度">
        <el-input-number v-model="uavAssetForm.speed" :min="0" :max="35" :precision="1" style="width: 100%" />
      </el-form-item>
      <el-form-item label="机巢状态">
        <el-input v-model="uavAssetForm.dockStatus" placeholder="例如：在线待命 / 自动充电" />
      </el-form-item>
      <el-form-item label="RTK 状态">
        <el-input v-model="uavAssetForm.rtkStatus" placeholder="例如：RTK 固定解" />
      </el-form-item>
      <el-form-item label="气象/空域" class="field-wide">
        <el-input v-model="uavAssetForm.dockWeather" placeholder="例如：风速 2.8m/s / 无降水 / 航线可飞" />
      </el-form-item>
      <el-form-item label="固件版本">
        <el-input v-model="uavAssetForm.firmware" placeholder="例如：Dock2 10.01 / Aircraft 09.02" />
      </el-form-item>
      <el-form-item label="挂载载荷">
        <el-input v-model="uavAssetForm.payload" placeholder="例如：广角/长焦/红外" />
      </el-form-item>
      <el-form-item label="视频回传" class="field-wide">
        <el-input v-model="uavAssetForm.videoReturn" placeholder="例如：4K 回传 25fps / 180ms" />
      </el-form-item>
      <el-form-item label="关联任务">
        <el-input v-model="uavAssetForm.activeTaskId" placeholder="例如：UAV-031" />
      </el-form-item>
      <el-form-item label="关联告警">
        <el-input v-model="uavAssetForm.relatedAlarm" placeholder="例如：A-20652" />
      </el-form-item>
    </el-form>
    <template #footer>
      <el-button :disabled="uavAssetSubmitting" @click="uavAssetDialog = false">取消</el-button>
        <el-button type="primary" :loading="uavAssetSubmitting" @click="submitUavAssetForm">保存无人机</el-button>
    </template>
  </el-dialog>

  <el-dialog
    v-model="cameraPreviewDialog"
    class="camera-preview-dialog"
    :width="cameraPreviewMode === 'fullscreen' ? '92vw' : 'min(92vw, 1280px)'"
    :title="cameraPreviewTitle"
    destroy-on-close
  >
    <template #header>
      <div class="camera-preview-header">
        <span>{{ cameraPreviewTitle }}</span>
        <el-switch :model-value="platform.sentinelEnabled" active-text="哨兵模式" @update:model-value="platform.setSentinelEnabled(Boolean($event))" />
      </div>
    </template>
    <template v-if="previewCamera">
      <StreamPlayer
        :camera="previewCamera"
        :sentinel="platform.sentinelEnabled"
        :show-actions="false"
        :capture-enabled="true"
        view-mode="focus4k"
        :prefer-capture-stream="true"
        :require-video-frame-for-capture="true"
      />
      <div class="preview-meta-grid">
        <span>通道</span><strong>{{ previewCamera.id }}</strong>
        <span>设备状态</span><strong>{{ previewCamera.status }}</strong>
        <span>接入协议</span><strong>{{ previewCamera.protocol }}</strong>
        <span>推理节点</span><strong>{{ previewCamera.node }}</strong>
        <span>坐标</span><strong>{{ cameraCoordinate(previewCamera) }}</strong>
        <span>推流地址</span><strong>{{ streamUrlOf(previewCamera) }}</strong>
      </div>
    </template>
  </el-dialog>

  <el-dialog
    v-model="alarmDrawer"
    class="alarm-review-dialog"
    width="860px"
    title="告警研判"
    destroy-on-close
    :close-on-click-modal="false"
    :close-on-press-escape="false"
    :show-close="true"
  >
    <template v-if="selectedAlarm">
      <div class="alarm-evidence-frame">
        <div class="alarm-review-video-head">
          <strong>告警证据片段</strong>
          <span>{{ selectedAlarmEvidenceTime || selectedAlarm.time }}</span>
        </div>
        <div class="alarm-evidence-canvas">
          <video
            v-if="selectedAlarmEvidenceMedia?.type === 'video'"
            class="alarm-evidence-media"
            :src="selectedAlarmEvidenceMedia.url"
            controls
            preload="metadata"
          />
          <img
            v-else-if="selectedAlarmEvidenceMedia?.type === 'image'"
            class="alarm-evidence-media"
            :src="selectedAlarmEvidenceMedia.url"
            :alt="`${selectedAlarmDeviceName || selectedAlarm.cameraName} 告警时刻证据`"
          />
          <div v-else class="alarm-evidence-backdrop">
            <strong>{{ selectedAlarmDeviceName || selectedAlarm.cameraName }}</strong>
            <span>{{ selectedAlarmEvidenceStatusText }}</span>
          </div>
          <span
            v-for="box in selectedAlarmEvidenceBoxes"
            :key="box.id"
            class="alarm-evidence-box"
            :style="evidenceBoxStyle(box)"
          >
            <b>{{ box.label }}</b>
            <em>{{ box.confidence }}%</em>
          </span>
          <div v-if="!selectedAlarmEvidenceBoxes.length" class="alarm-evidence-empty">未关联历史标注框</div>
        </div>
        <div class="alarm-review-video-meta">
          <span><b>设备名称</b><strong>{{ selectedAlarmDeviceName || selectedAlarm.cameraName }}</strong></span>
          <span><b>异常类型</b><strong>{{ selectedAlarm.type }}</strong></span>
          <span><b>证据来源</b><strong>{{ selectedAlarmEvidenceSource }}</strong></span>
        </div>
      </div>
      <div class="alarm-review-detail-grid">
        <span class="alarm-review-detail-item"><b>告警编号</b><strong>{{ selectedAlarm.id }}</strong></span>
        <span class="alarm-review-detail-item"><b>设备名称</b><strong>{{ selectedAlarmDeviceName || selectedAlarm.cameraName }}</strong></span>
        <span class="alarm-review-detail-item"><b>首次发生</b><strong>{{ selectedAggregateEvent ? formatEventDateTime(selectedAggregateEvent.firstOccurredAt) : (selectedAlarm.createdAt ? formatEventDateTime(selectedAlarm.createdAt) : selectedAlarm.time) }}</strong></span>
        <span class="alarm-review-detail-item"><b>告警等级</b><strong><StatusBadge :label="selectedAlarm.severity" :tone="severityTone(selectedAlarm.severity)" /></strong></span>
        <span class="alarm-review-detail-item"><b>经纬度</b><strong>{{ selectedAlarmCamera ? cameraCoordinate(selectedAlarmCamera) : '未配置' }}</strong></span>
        <span class="alarm-review-detail-item"><b>最近报警</b><strong>{{ selectedAggregateEvent ? formatEventDateTime(selectedAggregateEvent.latestOccurredAt) : (selectedAlarm.updatedAt ? formatEventDateTime(selectedAlarm.updatedAt) : selectedAlarm.time) }}</strong></span>
        <span class="alarm-review-detail-item"><b>处置人</b><strong>{{ selectedAlarm.owner }}</strong></span>
        <span class="alarm-review-detail-item"><b>处置工单</b><strong>{{ selectedAlarmWorkOrder ? `${selectedAlarmWorkOrder.id} / ${selectedAlarmWorkOrder.status}` : '待生成' }}</strong></span>
        <span class="alarm-review-detail-item"><b>当前状态</b><strong><StatusBadge :label="selectedAlarm.status" :tone="statusTone(selectedAlarm.status)" /></strong></span>
        <span class="alarm-review-detail-item"><b>归集统计</b><strong>{{ selectedAggregateEvent ? `${selectedAggregateEvent.occurrenceCount} 次 / 最高 ${selectedAggregateEvent.maxConfidence}%` : `${selectedAlarm.dedupeCount} 次 / 最高 ${selectedAlarm.confidence}%` }}</strong></span>
        <span class="alarm-review-detail-item"><b>证据包</b><strong>{{ selectedAlarmEvidence ? `${selectedAlarmEvidence.id} / ${selectedAlarmEvidence.status}` : '待组卷' }}</strong></span>
        <span class="alarm-review-detail-item"><b>复查任务</b><strong>{{ selectedAlarmUavTask ? `${selectedAlarmUavTask.id} / ${selectedAlarmUavTask.status}` : '未触发复查' }}</strong></span>
        <span class="alarm-review-detail-item"><b>研判建议</b><strong>{{ selectedAlarm.confidence >= 90 ? '建议已处理归档' : selectedAlarm.confidence >= 85 ? '建议人工复核后处置' : '建议忽略归档' }}</strong></span>
      </div>
      <div class="drawer-actions">
        <el-button :disabled="selectedAlarm.status === '误报' || selectedAlarm.status === '已归档'" @click="reviewSelectedAlarm('忽略')">忽略</el-button>
        <el-button type="primary" :disabled="selectedAlarm.status === '已归档'" @click="reviewSelectedAlarm('已处理')">已处理</el-button>
      </div>
    </template>
  </el-dialog>
  </div>
</template>
