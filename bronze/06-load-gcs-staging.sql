LOAD DATA OVERWRITE `trabalho1-pdm-2026.bronze._stg_blocks`
FROM FILES (
  format = 'PARQUET',
  uris = ['gs://trabalho1-pdm-2026-landing/blocks/blocks-*.parquet']
);

LOAD DATA OVERWRITE `trabalho1-pdm-2026.bronze._stg_transactions`
FROM FILES (
  format = 'PARQUET',
  uris = ['gs://trabalho1-pdm-2026-landing/transactions/tx-*.parquet']
);

LOAD DATA OVERWRITE `trabalho1-pdm-2026.bronze._stg_tx_pre2020_ref`
FROM FILES (
  format = 'PARQUET',
  uris = ['gs://trabalho1-pdm-2026-landing/tx_pre2020_ref/ref-*.parquet']
);
