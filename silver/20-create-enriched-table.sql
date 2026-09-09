CREATE OR REPLACE TABLE `trabalho1-pdm-2026.silver.tx_enriched`
PARTITION BY DATE(block_timestamp)
CLUSTER BY transaction_hash
OPTIONS (
  require_partition_filter = TRUE,
  description = 'Transações enriquecidas. Uma linha por transação, com agregações derivadas de outputs, inputs e idade de moeda. Limiar de dust em 546 satoshis (referência do Bitcoin Core para P2PKH), excluindo outputs de valor zero. OP_RETURN identificado por valor zero em scripts nonstandard, pois a categoria nulldata não é populada por este parser. Base para a matriz de features da camada Gold.'
) AS
WITH agg_outputs AS (
  SELECT
    transaction_hash,
    COUNT(*)                                           AS n_outputs,
    SUM(value_satoshi)                                 AS out_total,
    MAX(value_satoshi)                                 AS out_max,
    MIN(value_satoshi)                                 AS out_min,
    AVG(value_satoshi)                                 AS out_media,
    STDDEV_POP(value_satoshi)                          AS out_desvio,
    COUNT(DISTINCT value_satoshi)                      AS out_valores_distintos,
    COUNTIF(value_satoshi = 0)                         AS out_valor_zero,
    COUNTIF(value_satoshi > 0 AND value_satoshi < 546) AS out_dust,
    COUNTIF(script_type = 'nonstandard')               AS out_nonstandard,
    COUNTIF(script_type = 'multisig')                  AS out_multisig_script,
    COUNTIF(script_type LIKE 'witness%')               AS out_segwit,
    COUNTIF(address_count > 1)                         AS out_multi_endereco,
    COUNT(DISTINCT script_type)                        AS out_tipos_script
  FROM `trabalho1-pdm-2026.silver.tx_outputs`
  WHERE DATE(block_timestamp) BETWEEN DATE '2020-01-01' AND DATE '2020-12-31'
  GROUP BY transaction_hash
),
agg_inputs AS (
  SELECT
    transaction_hash,
    COUNT(*)                             AS n_inputs,
    SUM(value_satoshi)                   AS in_total,
    MAX(value_satoshi)                   AS in_max,
    MIN(value_satoshi)                   AS in_min,
    AVG(value_satoshi)                   AS in_media,
    STDDEV_POP(value_satoshi)            AS in_desvio,
    COUNT(DISTINCT address_single)       AS in_enderecos_unicos_distintos,
    COUNTIF(address_single IS NULL)      AS in_sem_endereco_unico,
    COUNTIF(script_type LIKE 'witness%') AS in_segwit,
    LOGICAL_OR(rbf_signaled)             AS rbf_signaled,
    COUNT(DISTINCT script_type)          AS in_tipos_script
  FROM `trabalho1-pdm-2026.silver.tx_inputs`
  WHERE DATE(block_timestamp) BETWEEN DATE '2020-01-01' AND DATE '2020-12-31'
  GROUP BY transaction_hash
),
agg_idade AS (
  SELECT
    transaction_hash,
    MAX(idade_dias)                  AS idade_max_dias,
    MIN(idade_dias)                  AS idade_min_dias,
    AVG(idade_dias)                  AS idade_media_dias,
    MAX(idade_blocos)                AS idade_max_blocos,
    MIN(idade_horas)                 AS idade_min_horas,
    MAX(idade_horas)                 AS idade_max_horas,
    COUNTIF(idade_dias > 365)        AS moedas_acima_1ano,
    LOGICAL_OR(origem_nao_resolvida) AS tem_origem_nao_resolvida
  FROM `trabalho1-pdm-2026.silver.coin_age`
  WHERE DATE(block_timestamp) BETWEEN DATE '2020-01-01' AND DATE '2020-12-31'
  GROUP BY transaction_hash
)
SELECT
  t.`hash`            AS transaction_hash,
  t.block_number,
  t.block_timestamp,
  TIMESTAMP_TRUNC(t.block_timestamp, HOUR) AS hora,
  t.is_coinbase,
  t.size,
  t.virtual_size,
  t.version,
  t.lock_time,
  t.input_count,
  t.output_count,
  t.input_value,
  t.output_value,
  t.fee,
  SAFE_DIVIDE(t.fee, t.virtual_size) AS fee_por_vbyte,

  o.n_outputs,
  o.out_total,
  o.out_max,
  o.out_min,
  o.out_media,
  o.out_desvio,
  o.out_valores_distintos,
  o.out_valor_zero,
  o.out_dust,
  o.out_nonstandard,
  o.out_multisig_script,
  o.out_segwit,
  o.out_multi_endereco,
  o.out_tipos_script,

  i.n_inputs,
  i.in_total,
  i.in_max,
  i.in_min,
  i.in_media,
  i.in_desvio,
  i.in_enderecos_unicos_distintos,
  i.in_sem_endereco_unico,
  i.in_segwit,
  i.rbf_signaled,
  i.in_tipos_script,

  a.idade_max_dias,
  a.idade_min_dias,
  a.idade_media_dias,
  a.idade_max_blocos,
  a.idade_min_horas,
  a.idade_max_horas,
  a.moedas_acima_1ano,
  a.tem_origem_nao_resolvida,

  '20260909-silver-v1' AS _batch_id,
  CURRENT_TIMESTAMP()  AS _processed_at

FROM `trabalho1-pdm-2026.bronze.transactions` AS t
LEFT JOIN agg_outputs AS o ON t.`hash` = o.transaction_hash
LEFT JOIN agg_inputs  AS i ON t.`hash` = i.transaction_hash
LEFT JOIN agg_idade   AS a ON t.`hash` = a.transaction_hash
WHERE DATE(t.block_timestamp) BETWEEN DATE '2020-01-01' AND DATE '2020-12-31';
