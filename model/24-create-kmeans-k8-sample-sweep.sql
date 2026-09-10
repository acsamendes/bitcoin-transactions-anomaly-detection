CREATE OR REPLACE MODEL `gold.kmeans_k8_1pct`
OPTIONS (
  model_type = 'KMEANS',
  num_clusters = 8,
  standardize_features = TRUE,
  kmeans_init_method = 'KMEANS++',
  max_iterations = 30
) AS
SELECT * EXCEPT (transaction_hash, block_timestamp, block_number, _batch_id, _processed_at)
FROM `gold.tx_features`
WHERE DATE(block_timestamp) BETWEEN DATE '2020-01-01' AND DATE '2020-12-31'
  AND MOD(ABS(FARM_FINGERPRINT(transaction_hash)), 100) = 0;

CREATE OR REPLACE MODEL `gold.kmeans_k8_10pct`
OPTIONS (
  model_type = 'KMEANS',
  num_clusters = 8,
  standardize_features = TRUE,
  kmeans_init_method = 'KMEANS++',
  max_iterations = 30
) AS
SELECT * EXCEPT (transaction_hash, block_timestamp, block_number, _batch_id, _processed_at)
FROM `gold.tx_features`
WHERE DATE(block_timestamp) BETWEEN DATE '2020-01-01' AND DATE '2020-12-31'
  AND MOD(ABS(FARM_FINGERPRINT(transaction_hash)), 10) = 0;

CREATE OR REPLACE MODEL `gold.kmeans_k8_full`
OPTIONS (
  model_type = 'KMEANS',
  num_clusters = 8,
  standardize_features = TRUE,
  kmeans_init_method = 'KMEANS++',
  max_iterations = 30
) AS
SELECT * EXCEPT (transaction_hash, block_timestamp, block_number, _batch_id, _processed_at)
FROM `gold.tx_features`
WHERE DATE(block_timestamp) BETWEEN DATE '2020-01-01' AND DATE '2020-12-31';
