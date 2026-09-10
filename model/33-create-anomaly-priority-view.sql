CREATE OR REPLACE VIEW `gold.v_anomaly_priority` AS
SELECT
  transaction_hash,
  block_timestamp,
  block_number,
  centroid_id,
  normalized_distance,
  is_anomaly,
  CASE
    WHEN normalized_distance >= 3.0   THEN 'alta'
    WHEN normalized_distance >= 2.241 THEN 'media'
    WHEN normalized_distance >= 1.685 THEN 'baixa'
    ELSE 'normal'
  END AS prioridade
FROM `gold.anomaly_scores`;
