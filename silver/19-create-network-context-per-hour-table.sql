CREATE OR REPLACE TABLE `trabalho1-pdm-2026.silver.network_context_hourly`
PARTITION BY DATE(hora)
CLUSTER BY hora
OPTIONS (
  require_partition_filter = TRUE,
  description = 'Estado agregado da rede Bitcoin por hora. Uma linha por hora cheia. Usado para normalizar features de transação em relação às condições de rede no momento da confirmação. Derivado de bronze.blocks e bronze.transactions.'
) AS
WITH blocos_hora AS (
  SELECT
    TIMESTAMP_TRUNC(timestamp, HOUR) AS hora,
    COUNT(*)                         AS blocos_na_hora,
    AVG(size)                        AS tamanho_medio_bloco,
    AVG(weight)                      AS peso_medio_bloco,
    AVG(transaction_count)           AS tx_media_por_bloco,
    SUM(transaction_count)           AS tx_total_hora,
    AVG(weight) / 4000000            AS ocupacao_media
  FROM `trabalho1-pdm-2026.bronze.blocks`
  WHERE DATE(timestamp) BETWEEN DATE '2020-01-01' AND DATE '2020-12-31'
  GROUP BY hora
),
taxas_hora AS (
  SELECT
    TIMESTAMP_TRUNC(block_timestamp, HOUR) AS hora,
    APPROX_QUANTILES(SAFE_DIVIDE(fee, virtual_size), 100)[OFFSET(50)] AS fee_vbyte_mediana,
    APPROX_QUANTILES(SAFE_DIVIDE(fee, virtual_size), 100)[OFFSET(90)] AS fee_vbyte_p90,
    AVG(SAFE_DIVIDE(fee, virtual_size))    AS fee_vbyte_media,
    AVG(fee)                               AS fee_media_satoshi,
    COUNT(*)                               AS tx_na_hora
  FROM `trabalho1-pdm-2026.bronze.transactions`
  WHERE DATE(block_timestamp) BETWEEN DATE '2020-01-01' AND DATE '2020-12-31'
    AND NOT is_coinbase
  GROUP BY hora
)
SELECT
  b.hora,
  b.blocos_na_hora,
  b.tamanho_medio_bloco,
  b.peso_medio_bloco,
  b.tx_media_por_bloco,
  b.tx_total_hora,
  b.ocupacao_media,
  t.fee_vbyte_mediana,
  t.fee_vbyte_p90,
  t.fee_vbyte_media,
  t.fee_media_satoshi,
  t.tx_na_hora,
  '20260909-silver-v1' AS _batch_id,
  CURRENT_TIMESTAMP()  AS _processed_at
FROM blocos_hora AS b
LEFT JOIN taxas_hora AS t USING (hora);
