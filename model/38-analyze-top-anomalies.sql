SELECT
  s.transaction_hash,
  DATE(s.block_timestamp)            AS dia,
  ROUND(s.normalized_distance, 2)    AS distancia,
  s.centroid_id,
  t.n_inputs,
  t.n_outputs,
  ROUND(t.out_total / 100000000, 4)  AS btc_total,
  t.idade_max_dias,
  ROUND(t.fee_por_vbyte, 1)          AS fee_vbyte
FROM `gold.anomaly_scores` s
JOIN `silver.tx_enriched` t USING (transaction_hash)
WHERE DATE(s.block_timestamp) BETWEEN DATE '2020-01-01' AND DATE '2020-12-31'
  AND DATE(t.block_timestamp) BETWEEN DATE '2020-01-01' AND DATE '2020-12-31'
  AND s.is_anomaly
ORDER BY s.normalized_distance DESC
LIMIT 20;
