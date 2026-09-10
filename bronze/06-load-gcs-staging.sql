LOAD DATA OVERWRITE `bronze._stg_blocks`
FROM FILES (
  format = 'PARQUET',
  uris = ['gs://${BUCKET}/blocks/blocks-*.parquet']
);

LOAD DATA OVERWRITE `bronze._stg_transactions`
FROM FILES (
  format = 'PARQUET',
  uris = ['gs://${BUCKET}/transactions/tx-*.parquet']
);

LOAD DATA OVERWRITE `bronze._stg_tx_pre2020_ref`
FROM FILES (
  format = 'PARQUET',
  uris = ['gs://${BUCKET}/tx_pre2020_ref/ref-*.parquet']
);
