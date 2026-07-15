import assert from 'node:assert/strict';
import test from 'node:test';
import { captureAndStoreAlarmEvidence, resolveEvidenceSource } from '../src/alarm-evidence.mjs';
import { createApp } from '../src/server.mjs';
import { createMemoryStore } from '../src/store.mjs';

test('prefers the inference source when resolving alarm evidence', () => {
  assert.equal(resolveEvidenceSource({
    sourceStreamUrl: 'rtsp://camera/inference',
    displayStreamUrl: 'http://gateway/live.m3u8',
  }), 'rtsp://camera/inference');
});

test('captures and stores one JPEG for a new alarm', async () => {
  let saved;
  const store = {
    async getAlarmEvidence() {
      return null;
    },
    async saveAlarmEvidence(record) {
      saved = record;
      return { ...record, byteSize: record.data.length };
    },
  };
  const result = await captureAndStoreAlarmEvidence(
    store,
    { id: 'A-EVIDENCE-1', cameraId: 'CH01', createdAt: '2026-07-12T10:00:00.000Z' },
    {
      eventId: 'AI-EVIDENCE-1',
      sourceStreamUrl: 'rtsp://camera/stream',
      generatedAt: '2026-07-12T10:00:00.000Z',
      coordinateSpace: 'normalized',
      boxes: [{ cls: '漂浮物', score: 0.91, x: 0.1, y: 0.2, w: 0.3, h: 0.4 }],
    },
    { captureFrame: async () => Buffer.from([0xff, 0xd8, 0xff, 0xd9]) },
  );

  assert.equal(saved.alarmId, 'A-EVIDENCE-1');
  assert.equal(saved.eventId, 'AI-EVIDENCE-1');
  assert.equal(saved.mimeType, 'image/jpeg');
  assert.equal(saved.coordinateSpace, 'normalized');
  assert.deepEqual(saved.annotations, [{ cls: '漂浮物', score: 0.91, x: 0.1, y: 0.2, w: 0.3, h: 0.4 }]);
  assert.equal(result.byteSize, 4);
});

test('does not recapture evidence that already exists', async () => {
  let captures = 0;
  const existing = { alarmId: 'A-EVIDENCE-2', mimeType: 'image/jpeg', byteSize: 123, capturedAt: '2026-07-12T10:00:00.000Z' };
  const store = {
    async getAlarmEvidence() {
      return existing;
    },
    async saveAlarmEvidence() {
      throw new Error('must not save');
    },
  };

  const result = await captureAndStoreAlarmEvidence(
    store,
    { id: 'A-EVIDENCE-2', cameraId: 'CH02' },
    { sourceStreamUrl: 'rtsp://camera/stream' },
    { captureFrame: async () => { captures += 1; return Buffer.from('unexpected'); } },
  );

  assert.equal(captures, 0);
  assert.equal(result.skipped, 'already-exists');
});

test('serves stored evidence as authenticated application media', async () => {
  const store = createMemoryStore();
  await store.saveAlarmEvidence({
    alarmId: 'A-EVIDENCE-HTTP',
    eventId: 'AI-EVIDENCE-HTTP',
    cameraId: 'CH01',
    mimeType: 'image/jpeg',
    data: Buffer.from([0xff, 0xd8, 0xff, 0xd9]),
    capturedAt: '2026-07-12T10:00:00.000Z',
  });
  const server = createApp({ store, authRequired: false });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  try {
    const address = server.address();
    const response = await fetch(`http://127.0.0.1:${address.port}/api/alarm/alarms/A-EVIDENCE-HTTP/evidence`);
    assert.equal(response.status, 200);
    assert.equal(response.headers.get('content-type'), 'image/jpeg');
    assert.deepEqual(Buffer.from(await response.arrayBuffer()), Buffer.from([0xff, 0xd8, 0xff, 0xd9]));
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});

test('serves persisted alarm annotations without depending on the recent event snapshot', async () => {
  const store = createMemoryStore();
  await store.saveAlarmEvidence({
    alarmId: 'A-EVIDENCE-META',
    eventId: 'AI-EVIDENCE-META',
    cameraId: 'CH04',
    mimeType: 'image/jpeg',
    data: Buffer.from([0xff, 0xd8, 0xff, 0xd9]),
    capturedAt: '2026-07-15T05:49:51.055Z',
    coordinateSpace: 'normalized',
    annotations: [{ cls: '水色异常', score: 0.88, x: 0.2, y: 0.3, w: 0.4, h: 0.25 }],
  });
  const server = createApp({ store, authRequired: false });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  try {
    const address = server.address();
    const response = await fetch(`http://127.0.0.1:${address.port}/api/alarm/alarms/A-EVIDENCE-META/evidence/metadata`);
    const payload = await response.json();
    assert.equal(response.status, 200);
    assert.equal(payload.data.eventId, 'AI-EVIDENCE-META');
    assert.equal(payload.data.coordinateSpace, 'normalized');
    assert.deepEqual(payload.data.boxes, [{ cls: '水色异常', score: 0.88, x: 0.2, y: 0.3, w: 0.4, h: 0.25 }]);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});

test('recovers annotations for legacy evidence through its linked AI event', async () => {
  const store = createMemoryStore();
  await store.saveAlarmEvidence({
    alarmId: 'A-EVIDENCE-LEGACY',
    eventId: 'AI-EVIDENCE-LEGACY',
    cameraId: 'CH01',
    mimeType: 'image/jpeg',
    data: Buffer.from([0xff, 0xd8, 0xff, 0xd9]),
    capturedAt: '2026-07-14T15:49:51.055Z',
  });
  store.getAiEvent = async () => ({
    id: 'AI-EVIDENCE-LEGACY',
    request: {
      coordinateSpace: 'normalized',
      detections: [{ cls: '漂浮物', score: 0.92, x: 0.12, y: 0.21, w: 0.31, h: 0.41 }],
    },
  });
  const server = createApp({ store, authRequired: false });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  try {
    const address = server.address();
    const response = await fetch(`http://127.0.0.1:${address.port}/api/alarm/alarms/A-EVIDENCE-LEGACY/evidence/metadata`);
    const payload = await response.json();
    assert.equal(response.status, 200);
    assert.deepEqual(payload.data.boxes, [{ cls: '漂浮物', score: 0.92, x: 0.12, y: 0.21, w: 0.31, h: 0.41 }]);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});
