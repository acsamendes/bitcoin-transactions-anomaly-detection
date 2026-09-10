CREATE OR REPLACE TABLE `gold.anomaly_scores`
PARTITION BY DATE(block_timestamp)
CLUSTER BY transaction_hash
OPTIONS (
  require_partition_filter = TRUE,
  description = 'Scores de anomalia por transação, gerados por ML.DETECT_ANOMALIES sobre o modelo KMeans com K=8 treinado em amostra determinística de 10%. Features não replicadas: disponíveis em gold.tx_features via transaction_hash. O parâmetro contamination de 0.01 define o percentil de corte e não é estimado pelo modelo; a distância normalizada é preservada para permitir reavaliação com outros limiares sem reprocessamento.'
) AS
SELECT
  transaction_hash,
  block_timestamp,
  block_number,
  is_anomaly,
  normalized_distance,
  CENTROID_ID AS centroid_id,
  '20260909-gold-v1'  AS _batch_id,
  CURRENT_TIMESTAMP() AS _processed_at
FROM ML.DETECT_ANOMALIES(
  MODEL `gold.kmeans_k8_10pct`,
  STRUCT(0.01 AS contamination),
  (
    SELECT * EXCEPT (_batch_id, _processed_at)
    FROM `gold.tx_features`
    WHERE DATE(block_timestamp) BETWEEN DATE '2020-01-01' AND DATE '2020-12-31'
  )
);
