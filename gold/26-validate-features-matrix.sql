SELECT
  COUNT(*) AS total,
  COUNTIF(f_log_valor_total IS NULL)      AS n_valor_total,
  COUNTIF(f_log_maior_output IS NULL)     AS n_maior_output,
  COUNTIF(f_log_taxa IS NULL)             AS n_taxa,
  COUNTIF(f_log_tamanho IS NULL)          AS n_tamanho,
  COUNTIF(f_log_n_inputs IS NULL)         AS n_inputs,
  COUNTIF(f_log_n_outputs IS NULL)        AS n_outputs,
  COUNTIF(f_repeticao_valores IS NULL)    AS n_repeticao,
  COUNTIF(f_razao_maior_output IS NULL)   AS n_razao_maior,
  COUNTIF(f_log_razao_in_out IS NULL)     AS n_razao_inout,
  COUNTIF(f_log_cv_outputs IS NULL)       AS n_cv,
  COUNTIF(f_log_taxa_relativa IS NULL)    AS n_taxa_rel,
  COUNTIF(f_log_idade_max IS NULL)        AS n_idade_max,
  COUNTIF(f_log_idade_media IS NULL)      AS n_idade_media,
  COUNTIF(f_log_dispersao_idade IS NULL)  AS n_disp_idade,
  COUNTIF(f_razao_moeda_antiga IS NULL)   AS n_moeda_antiga,
  COUNTIF(f_razao_out_segwit IS NULL)     AS n_segwit,
  COUNTIF(f_razao_size_vsize IS NULL)     AS n_size_vsize,
  COUNTIF(IS_NAN(f_log_cv_outputs))       AS nan_cv,
  COUNTIF(IS_INF(f_log_taxa_relativa))    AS inf_taxa
FROM `trabalho1-pdm-2026.gold.tx_features`
WHERE DATE(block_timestamp) BETWEEN DATE '2020-01-01' AND DATE '2020-12-31';
