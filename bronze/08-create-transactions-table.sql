CREATE OR REPLACE TABLE `bronze.transactions`
PARTITION BY DATE(block_timestamp)
CLUSTER BY `hash`
OPTIONS (
  require_partition_filter = TRUE,
  description = 'Transações Bitcoin 2020. Cópia fiel carregada da zona de aterrissagem gs://${BUCKET}/transactions/. Arrays reconstruídas em SQL para desfazer o encapsulamento LIST do formato Parquet e restaurar o schema nativo da fonte.'
) AS
SELECT
  t.* EXCEPT (inputs, outputs),

  ARRAY(
    SELECT AS STRUCT
      i.element.index,
      i.element.spent_transaction_hash,
      i.element.spent_output_index,
      i.element.script_asm,
      i.element.script_hex,
      i.element.sequence,
      i.element.required_signatures,
      i.element.type,
      ARRAY(SELECT a.element FROM UNNEST(i.element.addresses.list) AS a) AS addresses,
      i.element.value
    FROM UNNEST(t.inputs.list) AS i
    ORDER BY i.element.index
  ) AS inputs,

  ARRAY(
    SELECT AS STRUCT
      o.element.index,
      o.element.script_asm,
      o.element.script_hex,
      o.element.required_signatures,
      o.element.type,
      ARRAY(SELECT a.element FROM UNNEST(o.element.addresses.list) AS a) AS addresses,
      o.element.value
    FROM UNNEST(t.outputs.list) AS o
    ORDER BY o.element.index
  ) AS outputs,

  '20260909-bronze-v1' AS _batch_id,
  CURRENT_TIMESTAMP()  AS _ingested_at

FROM `bronze._stg_transactions` AS t;
