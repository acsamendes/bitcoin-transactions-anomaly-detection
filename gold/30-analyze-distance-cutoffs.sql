SELECT
  ROUND(APPROX_QUANTILES(normalized_distance, 1000)[OFFSET(500)], 3) AS p50,
  ROUND(APPROX_QUANTILES(normalized_distance, 1000)[OFFSET(900)], 3) AS p90,
  ROUND(APPROX_QUANTILES(normalized_distance, 1000)[OFFSET(950)], 3) AS p95,
  ROUND(APPROX_QUANTILES(normalized_distance, 1000)[OFFSET(990)], 3) AS p99,
  ROUND(APPROX_QUANTILES(normalized_distance, 1000)[OFFSET(999)], 3) AS p999,
  ROUND(MAX(normalized_distance), 3)                                 AS maximo,
  COUNTIF(normalized_distance >= 5)                                  AS acima_5,
  COUNTIF(normalized_distance >= 10)                                 AS acima_10,
  COUNTIF(normalized_distance >= 20)                                 AS acima_20
FROM `gold.anomaly_scores`
WHERE DATE(block_timestamp) BETWEEN DATE '2020-01-01' AND DATE '2020-12-31';
