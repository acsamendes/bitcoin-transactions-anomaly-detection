EXPORT DATA OPTIONS (
  uri = 'gs://${BUCKET}/transactions/tx-*.parquet',
  format = 'PARQUET', compression = 'ZSTD', overwrite = TRUE
) AS
SELECT *
FROM `bigquery-public-data.crypto_bitcoin.transactions`
WHERE block_timestamp_month BETWEEN DATE '2020-01-01' AND DATE '2020-12-01'
  AND DATE(block_timestamp) BETWEEN DATE '2020-01-01' AND DATE '2020-12-31';
