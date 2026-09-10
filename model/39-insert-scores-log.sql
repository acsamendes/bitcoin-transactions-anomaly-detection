DELETE FROM `gold._transformation_log` WHERE tabela_destino = 'gold.anomaly_scores';

INSERT INTO `gold._transformation_log`
  (batch_id, tabela_destino, tabela_origem, processed_at,
   periodo_inicio, periodo_fim, linhas_geradas, observacao)
SELECT
  '20260909-gold-v1', 'gold.anomaly_scores',
  'gold.tx_features + gold.kmeans_k8_10pct',
  MIN(_processed_at), DATE '2020-01-01', DATE '2020-12-31', COUNT(*),
  'Scores gerados por ML.DETECT_ANOMALIES com contamination de 0.01, parâmetro que define o percentil de corte e não é estimado pelo modelo. Modelo KMeans com K=8 treinado em amostra determinística de 10 por cento selecionada por FARM_FINGERPRINT. A comparação entre amostras de 1, 10 e 100 por cento mostrou que 10 por cento produziu o melhor Davies-Bouldin, evidenciando que o aumento do volume de treino não melhora monotonicamente a clusterização em KMeans devido à sensibilidade à inicialização.'
FROM `gold.anomaly_scores`
WHERE DATE(block_timestamp) BETWEEN DATE '2020-01-01' AND DATE '2020-12-31';
