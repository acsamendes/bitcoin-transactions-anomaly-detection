SELECT
  prioridade,
  COUNT(*) AS transacoes,
  ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 3) AS pct,
  ROUND(MIN(normalized_distance), 3) AS dist_min,
  ROUND(MAX(normalized_distance), 3) AS dist_max
FROM `gold.v_anomaly_priority`
WHERE DATE(block_timestamp) BETWEEN DATE '2020-01-01' AND DATE '2020-12-31'
GROUP BY prioridade
ORDER BY dist_min DESC;
