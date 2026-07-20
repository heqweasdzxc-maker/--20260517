from __future__ import annotations

import threading

import numpy as np

from group_pool_core import DeadlineScheduler, LatestFrameMailbox, filter_boxes


def test_latest_frame_mailbox_replaces_stale_frame() -> None:
    mailbox = LatestFrameMailbox()
    first = np.full((2, 2, 3), 1, dtype=np.uint8)
    latest = np.full((2, 2, 3), 9, dtype=np.uint8)

    mailbox.publish(first, captured_at=10.0)
    mailbox.publish(latest, captured_at=11.0)

    snapshot = mailbox.snapshot()
    assert snapshot is not None
    assert snapshot.generation == 2
    assert snapshot.captured_at == 11.0
    assert np.array_equal(snapshot.frame, latest)


def test_latest_frame_mailbox_snapshot_isolated_from_writer() -> None:
    mailbox = LatestFrameMailbox()
    frame = np.zeros((2, 2, 3), dtype=np.uint8)
    mailbox.publish(frame, captured_at=1.0)
    snapshot = mailbox.snapshot()
    assert snapshot is not None

    frame[:] = 7
    assert int(snapshot.frame.max()) == 0


def test_latest_frame_mailbox_is_thread_safe() -> None:
    mailbox = LatestFrameMailbox()

    def writer(offset: int) -> None:
        for value in range(offset, offset + 50):
            mailbox.publish(np.array([value], dtype=np.int64), float(value))

    threads = [threading.Thread(target=writer, args=(index * 100,)) for index in range(4)]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join()

    snapshot = mailbox.snapshot()
    assert snapshot is not None
    assert snapshot.generation == 200


def test_scheduler_uses_configured_deadlines() -> None:
    scheduler = DeadlineScheduler()
    scheduler.register("CH03", 6.0, now=0.0)
    scheduler.register("CH01", 4.0, now=0.0)
    scheduler.register("CH09", 2.0, now=0.0)

    assert scheduler.deadline_seconds("CH03") == 1.0 / 6.0
    assert scheduler.deadline_seconds("CH01") == 0.25
    assert scheduler.deadline_seconds("CH09") == 0.5


def test_scheduler_selects_earliest_due_channel_without_starvation() -> None:
    scheduler = DeadlineScheduler()
    scheduler.register("CH01", 4.0, now=0.0)
    scheduler.register("CH02", 4.0, now=0.0)

    first = scheduler.next_ready(0.0, {"CH01", "CH02"})
    assert first == "CH01"
    scheduler.mark_dispatched(first, 0.0)

    second = scheduler.next_ready(0.0, {"CH01", "CH02"})
    assert second == "CH02"


def test_scheduler_does_not_dispatch_before_deadline() -> None:
    scheduler = DeadlineScheduler()
    scheduler.register("CH01", 4.0, now=0.0)
    assert scheduler.next_ready(0.0, {"CH01"}) == "CH01"
    scheduler.mark_dispatched("CH01", 0.0)

    assert scheduler.next_ready(0.249, {"CH01"}) is None
    assert scheduler.next_ready(0.25, {"CH01"}) == "CH01"


def test_filter_boxes_uses_channel_confidence() -> None:
    boxes = [
        {"cls": "漂浮物", "score": 0.49},
        {"cls": "漂浮物", "score": 0.50},
        {"cls": "水色异常", "score": 0.91},
    ]

    assert filter_boxes(boxes, 0.50) == boxes[1:]


def test_filter_boxes_rejects_classes_outside_channel_allowlist() -> None:
    boxes = [
        {"cls": "漂浮物", "score": 0.82},
        {"cls": "墙体裂痕", "score": 0.93},
        {"cls": "水色异常", "score": 0.78},
    ]

    assert filter_boxes(boxes, 0.50, {"漂浮物", "水色异常"}) == [boxes[0], boxes[2]]

