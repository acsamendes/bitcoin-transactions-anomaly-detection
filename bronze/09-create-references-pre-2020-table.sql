CREATE OR REPLACE TABLE `bronze.tx_pre2020_ref`
CLUSTER BY `hash`
OPTIONS (
  description = 'Mapeamento entre hash de transação e timestamp de criação para transações anteriores a 2020. Usado para resolver a idade de moedas gastas em 2020 cujo UTXO nasceu fora do recorte. Carregado da zona de aterrissagem gs://${BUCKET}/tx_pre2020_ref/.'
) AS
SELECT
  *,
  '20260909-bronze-v1' AS _batch_id,
  CURRENT_TIMESTAMP()  AS _ingested_at
FROM `bronze._stg_tx_pre2020_ref`;
