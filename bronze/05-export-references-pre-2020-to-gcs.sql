EXPORT DATA OPTIONS (
  uri = 'gs://${BUCKET}/tx_pre2020_ref/ref-*.parquet',
  format = 'PARQUET', compression = 'ZSTD', overwrite = TRUE
) AS
SELECT `hash`, block_timestamp, block_number
FROM `bigquery-public-data.crypto_bitcoin.transactions`
WHERE block_timestamp_month < DATE '2020-01-01';
