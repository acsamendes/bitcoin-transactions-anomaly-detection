CREATE OR REPLACE MODEL `trabalho1-pdm-2026.gold.kmeans_k8`
OPTIONS (
  model_type = 'KMEANS',
  num_clusters = 8,
  standardize_features = TRUE,
  kmeans_init_method = 'KMEANS++',
  max_iterations = 30
) AS
SELECT * EXCEPT (transaction_hash, block_timestamp, block_number, _batch_id, _processed_at)
FROM `trabalho1-pdm-2026.gold.tx_features`
WHERE DATE(block_timestamp) BETWEEN DATE '2020-01-01' AND DATE '2020-12-31'
  AND MOD(ABS(FARM_FINGERPRINT(transaction_hash)), 100) = 0;
