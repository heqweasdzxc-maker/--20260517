# AI Runtime Topology And Model Registry Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Safely make group supervisors the only production inference path, activate the structure group with the dedicated model, and register both production models.

**Architecture:** A guarded operations-only deployment script preserves per-channel settings, activates and validates `group@structure` before retiring batch services, and restores all captured state on failure. A narrowly scoped SQL upsert records the two production models without changing unrelated records.

**Tech Stack:** Bash, systemd, Docker CLI, MySQL 8 JSON, Python unittest, SHA-256.

## Global Constraints

- Do not include or overwrite model weights.
- Do not modify camera, alarm threshold, backend, frontend, or stream-relay configuration.
- Keep group service definitions and environment files for rollback.
- Preserve all existing `rw_algorithm` records except the two stable IDs owned by this increment.
- Produce one compact incremental ZIP and SHA-256 sidecar.

---

### Task 1: Package Contract Tests

**Files:**
- Create: `river-watch-ai-runtime-topology-increment-20260714/tests/test_package.py`

**Interfaces:**
- Consumes: package directory layout.
- Produces: executable contract for preflight, rollback, model assignment, and package-size constraints.

- [ ] Write tests that require exact model paths, both MIGraphX checks, pre/post service checks, automatic rollback, two stable algorithm IDs, and the absence of `.onnx`/`.pt` files.
- [ ] Run `python -m unittest discover -s tests -v` and confirm failure because scripts and SQL do not exist.

### Task 2: Guarded Group-Only Cutover

**Files:**
- Create: `river-watch-ai-runtime-topology-increment-20260714/scripts/apply-ai-runtime-topology-increment-20260714.sh`
- Create: `river-watch-ai-runtime-topology-increment-20260714/scripts/verify-ai-runtime-topology-20260714.sh`
- Create: `river-watch-ai-runtime-topology-increment-20260714/scripts/rollback-ai-runtime-topology-20260714.sh`

**Interfaces:**
- Consumes: systemd units, group environment files, CH09/CH10 worker environments, and the existing dedicated structure model.
- Produces: group-only production state and a timestamped state backup under `/home/ai-river/river-watch/backups`.

- [ ] Verify the dedicated structure model hash and install it from the application model directory only when `/opt` lacks the verified copy.
- [ ] Preserve CH09/CH10 stream, token, confidence, and sampling settings while upserting only structure model/runtime keys.
- [ ] Capture active/enabled state before changes.
- [ ] Stop `batch@structure`, start `group@structure`, and poll until both child workers load the exact model on MIGraphX.
- [ ] Enable all three group units and disable both batch units only after successful group verification.
- [ ] Run post-checks and invoke rollback through an `ERR` trap on failure.
- [ ] Verify shell syntax with `bash -n` for all scripts.

### Task 3: Production Model Registry

**Files:**
- Create: `river-watch-ai-runtime-topology-increment-20260714/db/upsert-production-model-registry.sql`

**Interfaces:**
- Consumes: MySQL database selected by the running container environment.
- Produces: `ALG-RIVER-20260714` and `ALG-STRUCTURE-20260630` in `rw_algorithm`.

- [ ] Add parameter-free idempotent upserts using exact source paths and assignments.
- [ ] Preserve existing rows by limiting `ON DUPLICATE KEY UPDATE` to the same IDs.
- [ ] Include model metrics and channel scope in each JSON payload.

### Task 4: Packaging And Verification

**Files:**
- Create: `river-watch-ai-runtime-topology-increment-20260714/README.md`
- Create: `river-watch-ai-runtime-topology-increment-20260714/SHA256SUMS`

**Interfaces:**
- Consumes: tested scripts and SQL.
- Produces: deployable ZIP and SHA-256 sidecar.

- [ ] Run the Python package tests and shell syntax checks.
- [ ] Generate internal checksums without including the checksum file itself.
- [ ] Create the ZIP and verify it by clean extraction and `sha256sum -c SHA256SUMS`.
- [ ] Publish the increment and documentation to `heqweasdzxc-maker/--20260517`.

