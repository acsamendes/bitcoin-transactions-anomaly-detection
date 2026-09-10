DELETE FROM `silver._transformation_log` WHERE TRUE;

INSERT INTO `silver._transformation_log`
  (batch_id, tabela_destino, tabela_origem, processed_at,
   periodo_inicio, periodo_fim, linhas_geradas, observacao)
SELECT
  '20260909-silver-v1', 'silver.tx_outputs', 'bronze.transactions',
  MIN(_processed_at), DATE '2020-01-01', DATE '2020-12-31', COUNT(*),
  'Desaninhamento da array outputs via UNNEST. Valores em satoshi. Campos de script descartados. address_single preenchido apenas quando há exatamente um endereço, pois a ordem da array não implica hierarquia em multisig.'
FROM `silver.tx_outputs`
WHERE DATE(block_timestamp) BETWEEN DATE '2020-01-01' AND DATE '2020-12-31';

INSERT INTO `silver._transformation_log`
  (batch_id, tabela_destino, tabela_origem, processed_at,
   periodo_inicio, periodo_fim, linhas_geradas, observacao)
SELECT
  '20260909-silver-v1', 'silver.tx_inputs', 'bronze.transactions',
  MIN(_processed_at), DATE '2020-01-01', DATE '2020-12-31', COUNT(*),
  'Desaninhamento da array inputs via UNNEST. Valores em satoshi. Clusterizado por spent_transaction_hash em vez de transaction_hash para otimizar o join de idade de moeda. rbf_signaled conforme BIP125, sinalização aproximada.'
FROM `silver.tx_inputs`
WHERE DATE(block_timestamp) BETWEEN DATE '2020-01-01' AND DATE '2020-12-31';

INSERT INTO `silver._transformation_log`
  (batch_id, tabela_destino, tabela_origem, processed_at,
   periodo_inicio, periodo_fim, linhas_geradas, observacao)
SELECT
  '20260909-silver-v1', 'silver.tx_origin_index',
  'bronze.transactions + bronze.tx_pre2020_ref',
  MIN(_processed_at), NULL, DATE '2020-12-31', COUNT(*),
  'Índice unificado hash para timestamp de origem. Materializado como tabela física estreita e clusterizada por hash para otimizar o join de idade de moeda, reduzindo o custo estimado de aproximadamente 15 TB para menos de 100 GB.'
FROM `silver.tx_origin_index`;

INSERT INTO `silver._transformation_log`
  (batch_id, tabela_destino, tabela_origem, processed_at,
   periodo_inicio, periodo_fim, linhas_geradas, observacao)
SELECT
  '20260909-silver-v1', 'silver.coin_age',
  'silver.tx_inputs + silver.tx_origin_index',
  MIN(_processed_at), DATE '2020-01-01', DATE '2020-12-31', COUNT(*),
  'Resolução da origem temporal dos UTXOs gastos. Idade calculada em horas, dias e blocos. A união prévia das duas fontes de hash resolve a censura à esquerda para moedas criadas antes do recorte.'
FROM `silver.coin_age`
WHERE DATE(block_timestamp) BETWEEN DATE '2020-01-01' AND DATE '2020-12-31';

INSERT INTO `silver._transformation_log`
  (batch_id, tabela_destino, tabela_origem, processed_at,
   periodo_inicio, periodo_fim, linhas_geradas, observacao)
SELECT
  '20260909-silver-v1', 'silver.network_context_hourly',
  'bronze.blocks + bronze.transactions',
  MIN(_processed_at), DATE '2020-01-01', DATE '2020-12-31', COUNT(*),
  'Estado da rede agregado por hora UTC. Mediana e p90 de fee por vbyte via APPROX_QUANTILES, excluindo coinbase. Ocupação estimada sobre limite de peso de 4M por bloco.'
FROM `silver.network_context_hourly`
WHERE DATE(hora) BETWEEN DATE '2020-01-01' AND DATE '2020-12-31';

INSERT INTO `silver._transformation_log`
  (batch_id, tabela_destino, tabela_origem, processed_at,
   periodo_inicio, periodo_fim, linhas_geradas, observacao)
SELECT
  '20260909-silver-v1', 'silver.tx_enriched',
  'bronze.transactions + silver.tx_outputs + silver.tx_inputs + silver.coin_age',
  MIN(_processed_at), DATE '2020-01-01', DATE '2020-12-31', COUNT(*),
  'Consolidação por transação. LEFT JOIN a partir de bronze.transactions para preservar as 53.222 coinbase, que possuem array de inputs vazia. STDDEV_POP no lugar de STDDEV para evitar nulos em transações de elemento único. Limiar de dust definido para 546 satoshis, excluindo os zerados.'
FROM `silver.tx_enriched`
WHERE DATE(block_timestamp) BETWEEN DATE '2020-01-01' AND DATE '2020-12-31';
