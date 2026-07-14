# Alarm List Full Datetime Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Display every Alarm Center row as `YYYY-MM-DD HH:mm:ss` while preserving persisted-timestamp sorting.

**Architecture:** Add one focused formatter utility and invoke it only from the Alarm Center time-column slot. Reuse the persisted timestamp priority already used for sorting, with a conservative time-only fallback for legacy rows.

**Tech Stack:** Vue 3, TypeScript, Element Plus, Vitest, Vite

## Global Constraints

- Display timezone is `Asia/Shanghai`.
- Output format is exactly `YYYY-MM-DD HH:mm:ss`.
- Default order remains newest first using persisted timestamps.
- Backend, database, AI inference services and unrelated frontend pages remain unchanged.
- Delivery is a frontend-only incremental package with rollback.

## Task 1: Alarm datetime formatter

**Files:**
- Create: `codex-handoff/frontend/src/utils/alarmDateTime.ts`
- Create: `codex-handoff/frontend/src/__tests__/alarmDateTime.test.ts`
- Modify: `codex-handoff/frontend/src/views/pages/AlarmsPage.vue`
- Modify: `codex-handoff/frontend/src/__tests__/alarmsFilterLayout.test.ts`
- Modify: `codex-handoff/frontend/src/__tests__/alarmFlowSimplification.test.ts`

**Interfaces:**
- Consumes: `Alarm.updatedAt`, `Alarm.createdAt`, `Alarm.time`
- Produces: `formatAlarmDateTime(alarm: Alarm): string`

- [x] Write failing source and behavior tests.
- [x] Verify RED before implementation.
- [x] Implement the formatter and `日期时间` column slot.
- [x] Verify focused tests, full frontend tests and production build.

## Task 2: Incremental delivery

**Files:**
- Create: `river-watch-alarm-list-full-datetime-increment-20260714/README.md`
- Create: `river-watch-alarm-list-full-datetime-increment-20260714/scripts/apply-alarm-list-full-datetime-increment-20260714.sh`
- Include: changed source/test files and complete verified `frontend/dist`

**Interfaces:**
- Consumes: verified frontend source and build output
- Produces: reversible frontend-only deployment ZIP and SHA-256 file

- [ ] Build the incremental staging directory.
- [ ] Implement guarded hot deployment with automatic rollback.
- [ ] Verify the ZIP from a clean extraction.
- [ ] Publish the handoff record to GitHub.
