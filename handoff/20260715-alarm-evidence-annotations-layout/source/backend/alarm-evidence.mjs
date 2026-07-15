import { spawn } from 'node:child_process';

const pending = [];
let active = 0;

export function scheduleAlarmEvidenceCapture(store, alarm, payload = {}, options = {}) {
  if (!store?.getAlarmEvidence || !store?.saveAlarmEvidence || !alarm?.id) return false;
  const sourceUrl = resolveEvidenceSource(payload);
  if (!sourceUrl) return false;

  const maxPending = positiveInt(process.env.ALARM_EVIDENCE_QUEUE_MAX, 100);
  if (pending.length >= maxPending) pending.shift();
  pending.push({ store, alarm, payload, sourceUrl, options });
  drainQueue();
  return true;
}

export async function captureAndStoreAlarmEvidence(store, alarm, payload = {}, options = {}) {
  const existing = await store.getAlarmEvidence(alarm.id);
  if (existing) return { ...evidenceMetadata(existing), skipped: 'already-exists' };

  const sourceUrl = options.sourceUrl || resolveEvidenceSource(payload);
  if (!sourceUrl) return { skipped: 'missing-source' };

  const captureFrame = options.captureFrame || captureJpegFrame;
  const image = await captureFrame(sourceUrl, {
    timeoutMs: positiveInt(process.env.ALARM_EVIDENCE_CAPTURE_TIMEOUT_MS, 8000),
    maxBytes: positiveInt(process.env.ALARM_EVIDENCE_MAX_IMAGE_BYTES, 2 * 1024 * 1024),
    width: positiveInt(process.env.ALARM_EVIDENCE_WIDTH, 960),
  });
  if (!Buffer.isBuffer(image) || image.length === 0) throw new Error('captured evidence image is empty');

  const saved = await store.saveAlarmEvidence({
    alarmId: alarm.id,
    eventId: String(payload.eventId || payload.requestId || ''),
    cameraId: alarm.cameraId,
    mimeType: 'image/jpeg',
    data: image,
    capturedAt: payload.generatedAt || alarm.createdAt || new Date().toISOString(),
    coordinateSpace: String(payload.coordinateSpace || 'normalized'),
    annotations: evidenceAnnotations(payload),
  });
  return evidenceMetadata(saved);
}

export function resolveEvidenceSource(payload = {}) {
  const values = [
    payload.sourceStreamUrl,
    payload.inferenceStreamUrl,
    payload.streamUrl,
    payload.displayStreamUrl,
  ];
  return String(values.find((value) => /^\w+:\/\//.test(String(value || '').trim())) || '').trim();
}

export function evidenceAnnotations(payload = {}) {
  const boxes = Array.isArray(payload.boxes)
    ? payload.boxes
    : Array.isArray(payload.detections)
      ? payload.detections
      : [];
  return boxes.map((box) => ({ ...box }));
}

export function captureJpegFrame(sourceUrl, { timeoutMs = 8000, maxBytes = 2 * 1024 * 1024, width = 960 } = {}) {
  return new Promise((resolve, reject) => {
    const inputArgs = /^rtsp:/i.test(sourceUrl) ? ['-rtsp_transport', 'tcp'] : [];
    const args = [
      '-hide_banner',
      '-loglevel', 'error',
      ...inputArgs,
      '-i', sourceUrl,
      '-frames:v', '1',
      '-vf', `scale='min(${width},iw)':-2`,
      '-q:v', '6',
      '-f', 'image2pipe',
      '-vcodec', 'mjpeg',
      'pipe:1',
    ];
    const child = spawn(process.env.FFMPEG_BIN || 'ffmpeg', args, { stdio: ['ignore', 'pipe', 'pipe'] });
    const chunks = [];
    let size = 0;
    let stderr = '';
    let settled = false;
    let timer;

    const finish = (error, value) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      if (error) reject(error);
      else resolve(value);
    };

    child.stdout.on('data', (chunk) => {
      size += chunk.length;
      if (size > maxBytes) {
        child.kill('SIGKILL');
        finish(new Error(`evidence image exceeds ${maxBytes} bytes`));
        return;
      }
      chunks.push(chunk);
    });
    child.stderr.on('data', (chunk) => {
      if (stderr.length < 2000) stderr += chunk.toString('utf8');
    });
    child.on('error', (error) => finish(error));
    child.on('close', (code) => {
      if (code !== 0) return finish(new Error(`ffmpeg evidence capture failed (${code}): ${stderr.trim()}`));
      finish(null, Buffer.concat(chunks));
    });

    timer = setTimeout(() => {
      child.kill('SIGKILL');
      finish(new Error(`ffmpeg evidence capture timed out after ${timeoutMs}ms`));
    }, timeoutMs);
  });
}

function drainQueue() {
  const concurrency = positiveInt(process.env.ALARM_EVIDENCE_CAPTURE_CONCURRENCY, 2);
  while (active < concurrency && pending.length) {
    const task = pending.shift();
    active += 1;
    captureAndStoreAlarmEvidence(task.store, task.alarm, task.payload, { ...task.options, sourceUrl: task.sourceUrl })
      .catch((error) => {
        console.error(`[alarm-evidence] ${task.alarm.id}: ${error instanceof Error ? error.message : String(error)}`);
      })
      .finally(() => {
        active -= 1;
        drainQueue();
      });
  }
}

function evidenceMetadata(record = {}) {
  return {
    alarmId: record.alarmId,
    eventId: record.eventId || '',
    cameraId: record.cameraId || '',
    mimeType: record.mimeType || 'image/jpeg',
    byteSize: Number(record.byteSize || record.data?.length || 0),
    capturedAt: record.capturedAt || '',
    coordinateSpace: record.coordinateSpace || 'normalized',
    annotations: Array.isArray(record.annotations) ? record.annotations : [],
  };
}

function positiveInt(value, fallback) {
  const numeric = Number(value);
  return Number.isFinite(numeric) && numeric > 0 ? Math.floor(numeric) : fallback;
}
