import { spawn } from 'node:child_process';

const pending = [];
let active = 0;

export function scheduleAlarmEvidenceCapture(store, alarm, payload = {}, options = {}) {
  if (!store?.getAlarmEvidence || !store?.saveAlarmEvidence || !alarm?.id) return false;
  if (!payload?.evidenceFrame?.dataBase64) return false;

  const maxPending = positiveInt(process.env.ALARM_EVIDENCE_QUEUE_MAX, 100);
  if (pending.length >= maxPending) pending.shift();
  pending.push({ store, alarm, payload, options });
  drainQueue();
  return true;
}

export async function captureAndStoreAlarmEvidence(store, alarm, payload = {}, options = {}) {
  const existing = await store.getAlarmEvidence(alarm.id);
  if (existing) {
    assertPersistedEvidenceCamera(alarm, existing);
    return { ...evidenceMetadata(existing), skipped: 'already-exists' };
  }

  const embeddedImage = decodeEmbeddedEvidenceFrame(payload, alarm, {
    maxBytes: positiveInt(process.env.ALARM_EVIDENCE_MAX_IMAGE_BYTES, 2 * 1024 * 1024),
  });
  if (!embeddedImage) return { skipped: 'missing-exact-frame' };
  const image = embeddedImage;
  if (!Buffer.isBuffer(image) || image.length === 0) throw new Error('captured evidence image is empty');

  const saved = await store.saveAlarmEvidence({
    alarmId: alarm.id,
    eventId: String(payload.eventId || payload.requestId || ''),
    cameraId: alarm.cameraId,
    mimeType: 'image/jpeg',
    data: image,
    capturedAt: evidenceCapturedAt(payload, alarm),
    coordinateSpace: String(payload.coordinateSpace || 'normalized'),
    annotations: evidenceAnnotations(payload),
  });
  return evidenceMetadata(saved);
}

export function decodeEmbeddedEvidenceFrame(payload = {}, alarm = {}, { maxBytes = 2 * 1024 * 1024 } = {}) {
  const frame = payload?.evidenceFrame;
  if (!frame?.dataBase64) return null;
  assertEvidenceCamera(alarm, frame.cameraId);
  if (String(frame.mimeType || '').toLowerCase() !== 'image/jpeg') {
    throw new Error('embedded evidence frame must be image/jpeg');
  }
  const data = Buffer.from(String(frame.dataBase64), 'base64');
  if (!data.length || data.length > maxBytes || data[0] !== 0xff || data[1] !== 0xd8 || data.at(-2) !== 0xff || data.at(-1) !== 0xd9) {
    throw new Error('embedded evidence frame is invalid');
  }
  const markedCameraId = evidenceFrameCameraId(data);
  assertEvidenceCamera(alarm, markedCameraId);
  return data;
}

export function evidenceFrameCameraId(data) {
  if (!Buffer.isBuffer(data) || data.length < 8 || data[0] !== 0xff || data[1] !== 0xd8) return '';
  const prefix = Buffer.from('RIVERWATCH-EVIDENCE-V1|', 'ascii');
  let offset = 2;
  while (offset + 4 <= data.length && data[offset] === 0xff) {
    const marker = data[offset + 1];
    if (marker === 0xda || marker === 0xd9) break;
    const segmentLength = data.readUInt16BE(offset + 2);
    if (segmentLength < 2 || offset + 2 + segmentLength > data.length) break;
    if (marker === 0xfe) {
      const comment = data.subarray(offset + 4, offset + 2 + segmentLength);
      if (comment.subarray(0, prefix.length).equals(prefix)) {
        const camera = comment.subarray(prefix.length).toString('ascii').trim();
        return /^CH(?:0[1-9]|10)$/i.test(camera) ? camera.toUpperCase() : '';
      }
    }
    offset += 2 + segmentLength;
  }
  return '';
}

export function assertPersistedEvidenceCamera(alarm = {}, evidence = {}) {
  assertEvidenceCamera(alarm, evidence.cameraId);
  const markedCameraId = evidenceFrameCameraId(evidence.data);
  if (!markedCameraId) throw new Error('legacy evidence has no verifiable camera marker');
  assertEvidenceCamera(alarm, markedCameraId);
}

export function assertEvidenceCamera(alarm = {}, evidenceCameraId = '') {
  const alarmCameraId = String(alarm.cameraId || '').trim().toUpperCase();
  const actualCameraId = String(evidenceCameraId || '').trim().toUpperCase();
  if (!alarmCameraId || !actualCameraId || alarmCameraId !== actualCameraId) {
    throw new Error(`evidence camera does not match alarm camera: ${actualCameraId || 'missing'} != ${alarmCameraId || 'missing'}`);
  }
}

function evidenceCapturedAt(payload = {}, alarm = {}) {
  const capturedAtMs = Number(payload?.evidenceFrame?.capturedAtMs ?? payload.capturedAtMs);
  if (Number.isFinite(capturedAtMs) && capturedAtMs > 0) return new Date(capturedAtMs).toISOString();
  return payload.generatedAt || alarm.createdAt || new Date().toISOString();
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
    captureAndStoreAlarmEvidence(task.store, task.alarm, task.payload, task.options)
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
