from pathlib import Path


SCRIPT = (
    Path(__file__).resolve().parents[1]
    / "payload"
    / "scripts"
    / "apply-river-anomaly-model-increment-20260714-v2.sh"
)


def test_gpu_provider_wait_is_condition_based():
    text = SCRIPT.read_text(encoding="utf-8")

    assert "for i in $(seq 1 180); do" in text
    assert (
        'grep -Fq "$MODEL_NAME" <<<"$logs" && '
        "grep -Fq 'MIGraphXExecutionProvider'"
    ) in text
    assert "loaded the model but GPU provider was not confirmed" not in text


def test_known_runtime_errors_still_fail_immediately():
    text = SCRIPT.read_text(encoding="utf-8")
    error_check = text.index("InvalidArgument|Load model.*fail")
    success_check = text.index(
        'grep -Fq "$MODEL_NAME" <<<"$logs" && '
        "grep -Fq 'MIGraphXExecutionProvider'"
    )

    assert error_check < success_check
