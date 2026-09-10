CREATE OR REPLACE MODEL `gold.kmeans_k3`
OPTIONS (model_type='KMEANS', num_clusters=3, standardize_features=TRUE,
         kmeans_init_method='KMEANS++', max_iterations=30) AS
SELECT * EXCEPT (transaction_hash, block_timestamp, block_number, _batch_id, _processed_at)
FROM `gold.tx_features`
WHERE DATE(block_timestamp) BETWEEN DATE '2020-01-01' AND DATE '2020-12-31'
  AND MOD(ABS(FARM_FINGERPRINT(transaction_hash)), 100) = 0;

CREATE OR REPLACE MODEL `gold.kmeans_k5`
OPTIONS (model_type='KMEANS', num_clusters=5, standardize_features=TRUE,
         kmeans_init_method='KMEANS++', max_iterations=30) AS
SELECT * EXCEPT (transaction_hash, block_timestamp, block_number, _batch_id, _processed_at)
FROM `gold.tx_features`
WHERE DATE(block_timestamp) BETWEEN DATE '2020-01-01' AND DATE '2020-12-31'
  AND MOD(ABS(FARM_FINGERPRINT(transaction_hash)), 100) = 0;

CREATE OR REPLACE MODEL `gold.kmeans_k6`
OPTIONS (model_type='KMEANS', num_clusters=6, standardize_features=TRUE,
         kmeans_init_method='KMEANS++', max_iterations=30) AS
SELECT * EXCEPT (transaction_hash, block_timestamp, block_number, _batch_id, _processed_at)
FROM `gold.tx_features`
WHERE DATE(block_timestamp) BETWEEN DATE '2020-01-01' AND DATE '2020-12-31'
  AND MOD(ABS(FARM_FINGERPRINT(transaction_hash)), 100) = 0;

CREATE OR REPLACE MODEL `gold.kmeans_k12`
OPTIONS (model_type='KMEANS', num_clusters=12, standardize_features=TRUE,
         kmeans_init_method='KMEANS++', max_iterations=30) AS
SELECT * EXCEPT (transaction_hash, block_timestamp, block_number, _batch_id, _processed_at)
FROM `gold.tx_features`
WHERE DATE(block_timestamp) BETWEEN DATE '2020-01-01' AND DATE '2020-12-31'
  AND MOD(ABS(FARM_FINGERPRINT(transaction_hash)), 100) = 0;
