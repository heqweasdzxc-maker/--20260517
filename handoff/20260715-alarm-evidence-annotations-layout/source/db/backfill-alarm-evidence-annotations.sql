UPDATE rw_alarm_evidence AS evidence
JOIN rw_ai_event AS ai_event ON ai_event.id = evidence.event_id
SET evidence.annotation_data = JSON_OBJECT(
  'coordinateSpace', COALESCE(
    JSON_UNQUOTE(JSON_EXTRACT(ai_event.payload, '$.request.coordinateSpace')),
    'normalized'
  ),
  'boxes', COALESCE(
    JSON_EXTRACT(ai_event.payload, '$.request.boxes'),
    JSON_EXTRACT(ai_event.payload, '$.request.detections'),
    JSON_ARRAY()
  )
)
WHERE (
  evidence.annotation_data IS NULL
  OR COALESCE(JSON_LENGTH(JSON_EXTRACT(evidence.annotation_data, '$.boxes')), 0) = 0
)
AND COALESCE(
  JSON_LENGTH(JSON_EXTRACT(ai_event.payload, '$.request.boxes')),
  JSON_LENGTH(JSON_EXTRACT(ai_event.payload, '$.request.detections')),
  0
) > 0;

