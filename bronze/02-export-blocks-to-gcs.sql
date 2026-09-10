EXPORT DATA OPTIONS (
  uri = 'gs://${BUCKET}/blocks/blocks-*.parquet',
  format = 'PARQUET', compression = 'ZSTD', overwrite = TRUE
) AS
SELECT *
FROM `bigquery-public-data.crypto_bitcoin.blocks`
WHERE timestamp_month BETWEEN DATE '2020-01-01' AND DATE '2020-12-01'
  AND DATE(timestamp)  BETWEEN DATE '2020-01-01' AND DATE '2020-12-31';
