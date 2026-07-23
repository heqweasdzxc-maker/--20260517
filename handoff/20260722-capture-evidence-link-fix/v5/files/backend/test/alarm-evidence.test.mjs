import assert from 'node:assert/strict';
import test from 'node:test';
import {
  captureAndStoreAlarmEvidence,
  decodeEmbeddedEvidenceFrame,
  evidenceFrameCameraId,
  resolveEvidenceSource,
} from '../src/alarm-evidence.mjs';
import { createApp } from '../src/server.mjs';
import { createMemoryStore } from '../src/store.mjs';

function taggedJpeg(cameraId, body = Buffer.from([0x01, 0x02])) {
  const marker = Buffer.from(`RIVERWATCH-EVIDENCE-V1|${cameraId}`, 'ascii');
  return Buffer.concat([
    Buffer.from([0xff, 0xd8, 0xff, 0xfe, 0x00, marker.length + 2]),
    marker,
    body,
    Buffer.from([0xff, 0xd9]),
  ]);
}

async function createAlarm(store, id, cameraId) {
  await store.createAlarm({
    id,
    cameraId,
    cameraName: cameraId,
    type: 'floating',
    severity: 'general',
    confidence: 88,
    status: 'pending',
    time: '10:00:00',
    pts: '00:00:00.000',
    owner: 'AI',
    dedupeCount: 1,
  });
}

test('keeps inference stream resolution only for legacy diagnostics', () => {
  assert.equal(resolveEvidenceSource({
    sourceStreamUrl: 'rtsp://camera/inference',
    displayStreamUrl: 'http://gateway/live.m3u8',
  }), 'rtsp://camera/inference');
});

test('does not create historical evidence by reopening a live RTSP source', async () => {
  const store = {
    async getAlarmEvidence() { return null; },
    async saveAlarmEvidence() { throw new Error('source-only metadata must not be stored'); },
  };
  const result = await captureAndStoreAlarmEvidence(
    store,
    { id: 'A-SOURCE-ONLY', cameraId: 'CH01' },
    { eventId: 'AI-SOURCE-ONLY', sourceStreamUrl: 'rtsp://camera/stream' },
    { captureFrame: async () => { throw new Error('RTSP must not be reopened'); } },
  );
  assert.equal(result.skipped, 'missing-exact-frame');
});

test('stores the exact marked detection frame', async () => {
  const jpeg = taggedJpeg('CH02');
  let saved;
  const store = {
    async getAlarmEvidence() { return null; },
    async saveAlarmEvidence(record) {
      saved = record;
      return { ...record, byteSize: record.data.length };
    },
  };
  const result = await captureAndStoreAlarmEvidence(store, { id: 'A-EXACT', cameraId: 'CH02' }, {
    eventId: 'AI-EXACT',
    coordinateSpace: 'normalized',
    boxes: [{ cls: 'floating', score: 0.91 }],
    evidenceFrame: {
      cameraId: 'CH02',
      mimeType: 'image/jpeg',
      capturedAtMs: 1784680200000,
      dataBase64: jpeg.toString('base64'),
    },
  });
  assert.deepEqual(saved.data, jpeg);
  assert.equal(evidenceFrameCameraId(saved.data), 'CH02');
  assert.equal(saved.capturedAt, new Date(1784680200000).toISOString());
  assert.equal(result.byteSize, jpeg.length);
});

test('rejects an embedded frame marked for another camera', () => {
  const jpeg = taggedJpeg('CH09');
  assert.throws(
    () => decodeEmbeddedEvidenceFrame({
      evidenceFrame: { cameraId: 'CH02', mimeType: 'image/jpeg', dataBase64: jpeg.toString('base64') },
    }, { cameraId: 'CH02' }),
    /evidence camera does not match alarm camera/,
  );
});

test('does not recapture verified evidence that already exists', async () => {
  const existing = {
    alarmId: 'A-EXISTING',
    cameraId: 'CH02',
    mimeType: 'image/jpeg',
    byteSize: 123,
    data: taggedJpeg('CH02'),
    capturedAt: '2026-07-22T10:00:00.000Z',
  };
  const result = await captureAndStoreAlarmEvidence(
    { async getAlarmEvidence() { return existing; } },
    { id: 'A-EXISTING', cameraId: 'CH02' },
  );
  assert.equal(result.skipped, 'already-exists');
});

test('serves marked evidence and its persisted annotations', async () => {
  const store = createMemoryStore();
  await createAlarm(store, 'A-HTTP', 'CH04');
  const jpeg = taggedJpeg('CH04');
  await store.saveAlarmEvidence({
    alarmId: 'A-HTTP',
    eventId: 'AI-HTTP',
    cameraId: 'CH04',
    mimeType: 'image/jpeg',
    data: jpeg,
    capturedAt: '2026-07-22T10:00:00.000Z',
    coordinateSpace: 'normalized',
    annotations: [{ cls: 'floating', score: 0.88, x: 0.2, y: 0.3, w: 0.4, h: 0.25 }],
  });
  const server = createApp({ store, authRequired: false });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  try {
    const { port } = server.address();
    const media = await fetch(`http://127.0.0.1:${port}/api/alarm/alarms/A-HTTP/evidence`);
    const metadata = await fetch(`http://127.0.0.1:${port}/api/alarm/alarms/A-HTTP/evidence/metadata`);
    assert.equal(media.status, 200);
    assert.deepEqual(Buffer.from(await media.arrayBuffer()), jpeg);
    const payload = await metadata.json();
    assert.equal(metadata.status, 200);
    assert.equal(payload.data.cameraId, 'CH04');
    assert.deepEqual(payload.data.boxes, [{ cls: 'floating', score: 0.88, x: 0.2, y: 0.3, w: 0.4, h: 0.25 }]);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});

test('refuses evidence whose record or JPEG marker belongs to another camera', async () => {
  for (const [recordCamera, markerCamera] of [['CH09', 'CH09'], ['CH02', 'CH09']]) {
    const store = createMemoryStore();
    await createAlarm(store, 'A-MISMATCH', 'CH02');
    await store.saveAlarmEvidence({
      alarmId: 'A-MISMATCH', cameraId: recordCamera, mimeType: 'image/jpeg',
      data: taggedJpeg(markerCamera), capturedAt: '2026-07-22T10:00:00.000Z',
    });
    const server = createApp({ store, authRequired: false });
    await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
    try {
      const { port } = server.address();
      const media = await fetch(`http://127.0.0.1:${port}/api/alarm/alarms/A-MISMATCH/evidence`);
      const metadata = await fetch(`http://127.0.0.1:${port}/api/alarm/alarms/A-MISMATCH/evidence/metadata`);
      assert.equal(media.status, 409);
      assert.equal(metadata.status, 409);
    } finally {
      await new Promise((resolve) => server.close(resolve));
    }
  }
});

test('refuses all legacy evidence without a verifiable camera marker', async () => {
  const store = createMemoryStore();
  await createAlarm(store, 'A-LEGACY', 'CH02');
  await store.saveAlarmEvidence({
    alarmId: 'A-LEGACY', cameraId: 'CH02', mimeType: 'image/jpeg',
    data: Buffer.from([0xff, 0xd8, 0xff, 0xd9]), capturedAt: '2026-07-20T10:00:00.000Z',
  });
  const server = createApp({ store, authRequired: false });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  try {
    const { port } = server.address();
    const response = await fetch(`http://127.0.0.1:${port}/api/alarm/alarms/A-LEGACY/evidence`);
    assert.equal(response.status, 409);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});
