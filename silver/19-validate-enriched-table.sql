WITH base AS (
  SELECT *
  FROM `silver.tx_enriched`
  WHERE DATE(block_timestamp) BETWEEN DATE '2020-01-01' AND DATE '2020-12-31'
),
metricas AS (
  SELECT
    COUNT(*)                                              AS m_total,
    COUNTIF(is_coinbase)                                  AS m_coinbase,
    COUNTIF(n_inputs IS NULL)                             AS m_sem_agg_inputs,
    COUNTIF(n_outputs IS NULL)                            AS m_sem_agg_outputs,
    COUNTIF(NOT is_coinbase AND n_inputs IS NULL)         AS m_erro_join_inputs,
    COUNTIF(n_outputs <> output_count)                    AS m_div_outputs,
    COUNTIF(NOT is_coinbase AND n_inputs <> input_count)  AS m_div_inputs,
    COUNTIF(out_desvio IS NULL)                           AS m_desvio_nulo,
    COUNTIF(fee < 0)                                      AS m_fee_negativa,
    COUNTIF(NOT is_coinbase AND in_total < out_total)     AS m_out_maior_in,
    COUNTIF(tem_origem_nao_resolvida)                     AS m_origem_nao_resolvida,
    COUNTIF(out_valor_zero > 0)                           AS m_output_zero,
    COUNTIF(out_dust > 0)                                 AS m_dust,
    COUNTIF(out_nonstandard > 0)                          AS m_nonstandard,
    COUNTIF(out_segwit > 0)                               AS m_out_segwit,
    COUNTIF(in_segwit > 0)                                AS m_in_segwit,
    COUNTIF(rbf_signaled)                                 AS m_rbf,
    COUNTIF(n_outputs >= 10 AND out_valores_distintos <= 2) AS m_coinjoin,
    COUNTIF(idade_max_dias > 1825)                        AS m_moeda_5anos,
    MIN(DATE(block_timestamp))                            AS m_inicio,
    MAX(DATE(block_timestamp))                            AS m_fim
  FROM base
)
SELECT * FROM (
  SELECT 1 AS ord, 'total de transações'        AS verificacao, CAST(m_total AS STRING) AS valor,
         IF(m_total = 112553498, 'OK', 'FALHA') AS status FROM metricas
  UNION ALL SELECT 2, 'transações coinbase', CAST(m_coinbase AS STRING),
         IF(m_coinbase = 53222, 'OK', 'FALHA') FROM metricas
  UNION ALL SELECT 3, 'sem agregação de inputs (deve = coinbase)', CAST(m_sem_agg_inputs AS STRING),
         IF(m_sem_agg_inputs = m_coinbase, 'OK', 'FALHA') FROM metricas
  UNION ALL SELECT 4, 'sem agregação de outputs', CAST(m_sem_agg_outputs AS STRING),
         IF(m_sem_agg_outputs = 0, 'OK', 'FALHA') FROM metricas
  UNION ALL SELECT 5, 'erro de join em inputs', CAST(m_erro_join_inputs AS STRING),
         IF(m_erro_join_inputs = 0, 'OK', 'FALHA') FROM metricas
  UNION ALL SELECT 6, 'divergência n_outputs vs output_count', CAST(m_div_outputs AS STRING),
         IF(m_div_outputs = 0, 'OK', 'FALHA') FROM metricas
  UNION ALL SELECT 7, 'divergência n_inputs vs input_count', CAST(m_div_inputs AS STRING),
         IF(m_div_inputs = 0, 'OK', 'FALHA') FROM metricas
  UNION ALL SELECT 8, 'desvio padrão nulo', CAST(m_desvio_nulo AS STRING),
         IF(m_desvio_nulo = 0, 'OK', 'FALHA') FROM metricas
  UNION ALL SELECT 9, 'taxa negativa (impossível)', CAST(m_fee_negativa AS STRING),
         IF(m_fee_negativa = 0, 'OK', 'FALHA') FROM metricas
  UNION ALL SELECT 10, 'outputs maiores que inputs (impossível)', CAST(m_out_maior_in AS STRING),
         IF(m_out_maior_in = 0, 'OK', 'FALHA') FROM metricas
  UNION ALL SELECT 11, 'origem de moeda não resolvida', CAST(m_origem_nao_resolvida AS STRING),
         IF(m_origem_nao_resolvida = 0, 'OK', 'FALHA') FROM metricas
  UNION ALL SELECT 12, 'período inicial', CAST(m_inicio AS STRING),
         IF(m_inicio = DATE '2020-01-01', 'OK', 'FALHA') FROM metricas
  UNION ALL SELECT 13, 'período final', CAST(m_fim AS STRING),
         IF(m_fim = DATE '2020-12-31', 'OK', 'FALHA') FROM metricas
  UNION ALL SELECT 14, 'feature: output de valor zero', CAST(m_output_zero AS STRING),
         IF(m_output_zero > 0, 'OK', 'FEATURE MORTA') FROM metricas
  UNION ALL SELECT 15, 'feature: dust', CAST(m_dust AS STRING),
         IF(m_dust > 0, 'OK', 'FEATURE MORTA') FROM metricas
  UNION ALL SELECT 16, 'feature: script nonstandard', CAST(m_nonstandard AS STRING),
         IF(m_nonstandard > 0, 'OK', 'FEATURE MORTA') FROM metricas
  UNION ALL SELECT 17, 'feature: output segwit', CAST(m_out_segwit AS STRING),
         IF(m_out_segwit > 0, 'OK', 'FEATURE MORTA') FROM metricas
  UNION ALL SELECT 18, 'feature: input segwit', CAST(m_in_segwit AS STRING),
         IF(m_in_segwit > 0, 'OK', 'FEATURE MORTA') FROM metricas
  UNION ALL SELECT 19, 'feature: sinalização RBF', CAST(m_rbf AS STRING),
         IF(m_rbf > 0, 'OK', 'FEATURE MORTA') FROM metricas
  UNION ALL SELECT 20, 'padrão: candidatas a CoinJoin', CAST(m_coinjoin AS STRING),
         IF(m_coinjoin > 0, 'OK', 'FEATURE MORTA') FROM metricas
  UNION ALL SELECT 21, 'padrão: moeda dormente acima de 5 anos', CAST(m_moeda_5anos AS STRING),
         IF(m_moeda_5anos > 0, 'OK', 'FEATURE MORTA') FROM metricas
)
ORDER BY ord;
