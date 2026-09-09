INSERT INTO `trabalho1-pdm-2026.gold._transformation_log`
  (batch_id, tabela_destino, tabela_origem, processed_at,
   periodo_inicio, periodo_fim, linhas_geradas, observacao)
SELECT
  '20260909-gold-v1', 'gold.tx_features',
  'silver.tx_enriched + silver.network_context_hourly',
  MIN(_processed_at), DATE '2020-01-01', DATE '2020-12-31', COUNT(*),
  'Matriz com 21 features. Transformação logarítmica aplicada iterativamente após análise de variância: n_inputs, n_outputs, razao_in_out, taxa_relativa, dispersao_idade e cv_outputs excediam 50 desvios até o valor máximo e dominariam o cálculo de distância do KMeans. Feature de proporção de dust removida por desvio padrão de 0.012. Coinbase excluídas por não possuírem inputs nem taxa comparável.'
FROM `trabalho1-pdm-2026.gold.tx_features`
WHERE DATE(block_timestamp) BETWEEN DATE '2020-01-01' AND DATE '2020-12-31';
