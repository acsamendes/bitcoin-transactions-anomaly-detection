CREATE OR REPLACE TABLE `trabalho1-pdm-2026.gold.tx_features`
PARTITION BY DATE(block_timestamp)
CLUSTER BY transaction_hash
OPTIONS (
  require_partition_filter = TRUE,
  description = 'Matriz de features para detecção de anomalias. Uma linha por transação não coinbase, 21 features. Transformação logarítmica aplicada às features que excediam 50 desvios até o valor máximo na análise de variância, evitando que dominassem o cálculo de distância do KMeans. Feature de proporção de dust removida por desvio padrão de 0.012. Coinbase excluídas por não possuírem inputs nem taxa comparável.'
) AS
SELECT
  t.transaction_hash,
  t.block_timestamp,
  t.block_number,

  -- Escala
  LOG(t.out_total + 1)                                        AS f_log_valor_total,
  LOG(t.out_max + 1)                                          AS f_log_maior_output,
  LOG(t.fee + 1)                                              AS f_log_taxa,
  LOG(t.virtual_size + 1)                                     AS f_log_tamanho,

  -- Estrutura
  LOG(t.n_inputs + 1)                                         AS f_log_n_inputs,
  LOG(t.n_outputs + 1)                                        AS f_log_n_outputs,
  IFNULL(1 - SAFE_DIVIDE(t.out_valores_distintos, t.n_outputs), 0) AS f_repeticao_valores,
  IF(t.n_outputs >= 5
     AND IFNULL(SAFE_DIVIDE(t.out_valores_distintos, t.n_outputs), 1) <= 0.5, 1, 0) AS f_padrao_mistura,
  IFNULL(SAFE_DIVIDE(t.out_max, NULLIF(t.out_total, 0)), 1)   AS f_razao_maior_output,
  LOG(IFNULL(SAFE_DIVIDE(t.n_inputs, t.n_outputs), 0) + 1)    AS f_log_razao_in_out,
  LOG(IFNULL(SAFE_DIVIDE(t.out_desvio, NULLIF(t.out_media, 0)), 0) + 1) AS f_log_cv_outputs,

  -- Contexto de rede
  LOG(IFNULL(SAFE_DIVIDE(t.fee_por_vbyte, NULLIF(n.fee_vbyte_mediana, 0)), 1) + 1) AS f_log_taxa_relativa,

  -- Dormência
  LOG(IFNULL(t.idade_max_dias, 0) + 1)                        AS f_log_idade_max,
  LOG(IFNULL(t.idade_media_dias, 0) + 1)                      AS f_log_idade_media,
  LOG(IFNULL(SAFE_DIVIDE(t.idade_max_dias, NULLIF(t.idade_media_dias, 0)), 1) + 1) AS f_log_dispersao_idade,
  IF(IFNULL(t.idade_min_horas, 999) < 1, 1, 0)                AS f_gasto_imediato,
  IFNULL(SAFE_DIVIDE(t.moedas_acima_1ano, t.n_inputs), 0)     AS f_razao_moeda_antiga,

  -- Composição
  IFNULL(SAFE_DIVIDE(t.out_segwit, t.n_outputs), 0)           AS f_razao_out_segwit,
  IFNULL(SAFE_DIVIDE(t.size, NULLIF(t.virtual_size, 0)), 1)   AS f_razao_size_vsize,

  -- Comportamento
  IF(t.rbf_signaled, 1, 0)                                    AS f_rbf,
  IF(t.lock_time > 0, 1, 0)                                   AS f_locktime,

  '20260909-gold-v1'  AS _batch_id,
  CURRENT_TIMESTAMP() AS _processed_at

FROM `trabalho1-pdm-2026.silver.tx_enriched` AS t
LEFT JOIN `trabalho1-pdm-2026.silver.network_context_hourly` AS n
  ON t.hora = n.hora
 AND DATE(n.hora) BETWEEN DATE '2020-01-01' AND DATE '2020-12-31'
WHERE DATE(t.block_timestamp) BETWEEN DATE '2020-01-01' AND DATE '2020-12-31'
  AND NOT t.is_coinbase;
