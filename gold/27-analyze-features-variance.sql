WITH base AS (
  SELECT *
  FROM `gold.tx_features`
  WHERE DATE(block_timestamp) BETWEEN DATE '2020-01-01' AND DATE '2020-12-31'
),
stats AS (
  SELECT 'f_log_valor_total' AS feature, AVG(f_log_valor_total) AS media, STDDEV(f_log_valor_total) AS desvio, MIN(f_log_valor_total) AS minimo, MAX(f_log_valor_total) AS maximo FROM base
  UNION ALL SELECT 'f_log_maior_output', AVG(f_log_maior_output), STDDEV(f_log_maior_output), MIN(f_log_maior_output), MAX(f_log_maior_output) FROM base
  UNION ALL SELECT 'f_log_taxa', AVG(f_log_taxa), STDDEV(f_log_taxa), MIN(f_log_taxa), MAX(f_log_taxa) FROM base
  UNION ALL SELECT 'f_log_tamanho', AVG(f_log_tamanho), STDDEV(f_log_tamanho), MIN(f_log_tamanho), MAX(f_log_tamanho) FROM base
  UNION ALL SELECT 'f_log_n_inputs', AVG(f_log_n_inputs), STDDEV(f_log_n_inputs), MIN(f_log_n_inputs), MAX(f_log_n_inputs) FROM base
  UNION ALL SELECT 'f_log_n_outputs', AVG(f_log_n_outputs), STDDEV(f_log_n_outputs), MIN(f_log_n_outputs), MAX(f_log_n_outputs) FROM base
  UNION ALL SELECT 'f_repeticao_valores', AVG(f_repeticao_valores), STDDEV(f_repeticao_valores), MIN(f_repeticao_valores), MAX(f_repeticao_valores) FROM base
  UNION ALL SELECT 'f_padrao_mistura', AVG(f_padrao_mistura), STDDEV(f_padrao_mistura), MIN(f_padrao_mistura), MAX(f_padrao_mistura) FROM base
  UNION ALL SELECT 'f_razao_maior_output', AVG(f_razao_maior_output), STDDEV(f_razao_maior_output), MIN(f_razao_maior_output), MAX(f_razao_maior_output) FROM base
  UNION ALL SELECT 'f_log_razao_in_out', AVG(f_log_razao_in_out), STDDEV(f_log_razao_in_out), MIN(f_log_razao_in_out), MAX(f_log_razao_in_out) FROM base
  UNION ALL SELECT 'f_log_cv_outputs', AVG(f_log_cv_outputs), STDDEV(f_log_cv_outputs), MIN(f_log_cv_outputs), MAX(f_log_cv_outputs) FROM base
  UNION ALL SELECT 'f_log_taxa_relativa', AVG(f_log_taxa_relativa), STDDEV(f_log_taxa_relativa), MIN(f_log_taxa_relativa), MAX(f_log_taxa_relativa) FROM base
  UNION ALL SELECT 'f_log_idade_max', AVG(f_log_idade_max), STDDEV(f_log_idade_max), MIN(f_log_idade_max), MAX(f_log_idade_max) FROM base
  UNION ALL SELECT 'f_log_idade_media', AVG(f_log_idade_media), STDDEV(f_log_idade_media), MIN(f_log_idade_media), MAX(f_log_idade_media) FROM base
  UNION ALL SELECT 'f_log_dispersao_idade', AVG(f_log_dispersao_idade), STDDEV(f_log_dispersao_idade), MIN(f_log_dispersao_idade), MAX(f_log_dispersao_idade) FROM base
  UNION ALL SELECT 'f_gasto_imediato', AVG(f_gasto_imediato), STDDEV(f_gasto_imediato), MIN(f_gasto_imediato), MAX(f_gasto_imediato) FROM base
  UNION ALL SELECT 'f_razao_moeda_antiga', AVG(f_razao_moeda_antiga), STDDEV(f_razao_moeda_antiga), MIN(f_razao_moeda_antiga), MAX(f_razao_moeda_antiga) FROM base
  UNION ALL SELECT 'f_razao_out_segwit', AVG(f_razao_out_segwit), STDDEV(f_razao_out_segwit), MIN(f_razao_out_segwit), MAX(f_razao_out_segwit) FROM base
  UNION ALL SELECT 'f_razao_size_vsize', AVG(f_razao_size_vsize), STDDEV(f_razao_size_vsize), MIN(f_razao_size_vsize), MAX(f_razao_size_vsize) FROM base
  UNION ALL SELECT 'f_rbf', AVG(f_rbf), STDDEV(f_rbf), MIN(f_rbf), MAX(f_rbf) FROM base
  UNION ALL SELECT 'f_locktime', AVG(f_locktime), STDDEV(f_locktime), MIN(f_locktime), MAX(f_locktime) FROM base
)
SELECT
  feature,
  ROUND(media, 4)  AS media,
  ROUND(desvio, 4) AS desvio,
  ROUND(minimo, 3) AS minimo,
  ROUND(maximo, 3) AS maximo,
  ROUND(SAFE_DIVIDE(desvio, NULLIF(ABS(media), 0)), 2) AS cv,
  ROUND(SAFE_DIVIDE(maximo - media, NULLIF(desvio, 0)), 1) AS desvios_ate_max,
  CASE
    WHEN desvio < 0.01 THEN 'VARIANCIA BAIXA'
    WHEN SAFE_DIVIDE(maximo - media, NULLIF(desvio, 0)) > 50 THEN 'CAUDA PESADA'
    ELSE 'OK'
  END AS status
FROM stats
ORDER BY status DESC, cv DESC;
