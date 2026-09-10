WITH scores AS (
  SELECT transaction_hash, is_anomaly
  FROM `gold.anomaly_scores`
  WHERE DATE(block_timestamp) BETWEEN DATE '2020-01-01' AND DATE '2020-12-31'
),
heuristicas AS (
  SELECT
    transaction_hash,
    n_outputs >= 10 AND out_valores_distintos <= 2 AS repeticao_valores,
    idade_max_dias > 1825                          AS moeda_dormente,
    n_outputs >= 100                               AS muitos_outputs,
    n_inputs  >= 100                               AS muitos_inputs
  FROM `silver.tx_enriched`
  WHERE DATE(block_timestamp) BETWEEN DATE '2020-01-01' AND DATE '2020-12-31'
    AND NOT is_coinbase
),
j AS (
  SELECT h.*, s.is_anomaly
  FROM heuristicas h JOIN scores s USING (transaction_hash)
)
SELECT
  'Alta repeticao de valores (>= 10 outputs, <= 2 valores distintos)' AS heuristica,
  COUNTIF(repeticao_valores)                     AS selecionadas_pela_regra,
  COUNTIF(repeticao_valores AND is_anomaly)      AS tambem_marcadas_pelo_modelo,
  ROUND(100 * SAFE_DIVIDE(COUNTIF(repeticao_valores AND is_anomaly), COUNTIF(repeticao_valores)), 1) AS pct_concordancia
FROM j
UNION ALL
SELECT
  'Moeda dormente (UTXO gasto com mais de 5 anos)',
  COUNTIF(moeda_dormente),
  COUNTIF(moeda_dormente AND is_anomaly),
  ROUND(100 * SAFE_DIVIDE(COUNTIF(moeda_dormente AND is_anomaly), COUNTIF(moeda_dormente)), 1)
FROM j
UNION ALL
SELECT
  'Alta contagem de outputs (>= 100)',
  COUNTIF(muitos_outputs),
  COUNTIF(muitos_outputs AND is_anomaly),
  ROUND(100 * SAFE_DIVIDE(COUNTIF(muitos_outputs AND is_anomaly), COUNTIF(muitos_outputs)), 1)
FROM j
UNION ALL
SELECT
  'Alta contagem de inputs (>= 100)',
  COUNTIF(muitos_inputs),
  COUNTIF(muitos_inputs AND is_anomaly),
  ROUND(100 * SAFE_DIVIDE(COUNTIF(muitos_inputs AND is_anomaly), COUNTIF(muitos_inputs)), 1)
FROM j
UNION ALL
SELECT
  'Baseline: todas as transacoes',
  COUNT(*),
  COUNTIF(is_anomaly),
  ROUND(100 * SAFE_DIVIDE(COUNTIF(is_anomaly), COUNT(*)), 1)
FROM j
ORDER BY pct_concordancia DESC;
