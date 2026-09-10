SELECT
  COUNT(*)                                           AS total,
  COUNTIF(is_anomaly)                                AS anomalias,
  ROUND(100 * COUNTIF(is_anomaly) / COUNT(*), 3)     AS pct_anomalias,
  COUNT(DISTINCT centroid_id)                        AS clusters_usados,
  COUNTIF(normalized_distance IS NULL)               AS score_nulo,
  MIN(DATE(block_timestamp))                         AS inicio,
  MAX(DATE(block_timestamp))                         AS fim
FROM `gold.anomaly_scores`
WHERE DATE(block_timestamp) BETWEEN DATE '2020-01-01' AND DATE '2020-12-31';
