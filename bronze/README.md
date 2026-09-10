# Camada Bronze

Dado de entrada como ele existe na origem, sai o dado particionado, clusterizado e rastreável.

---

## Sumário

- [Princípio da camada](#princípio-da-camada)
- [Zona de aterrissagem no GCS](#zona-de-aterrissagem-no-gcs)
- [Tabelas produzidas](#tabelas-produzidas)
- [O problema do encapsulamento LIST](#o-problema-do-encapsulamento-list)
- [Decisões e justificativas](#decisões-e-justificativas)
- [Metadados e rastreabilidade](#metadados-e-rastreabilidade)
- [Validação](#validação)
- [Ordem de execução](#ordem-de-execução)

---

## Princípio da camada

Bronze significa cópia fiel da fonte, não bytes crus. A fonte aqui é o dataset público `bigquery-public-data.crypto_bitcoin`.

O que a camada faz:

- Recorta o período de interesse (2020 completo)
- Preserva **todas** as colunas da origem
- Adiciona particionamento, clustering e proteção contra varredura completa
- Adiciona metadados de ingestão

O que a camada **não** faz:

- Não filtra colunas por utilidade analítica
- Não converte unidades
- Não deriva campos calculados
- Não remove nem trata registros

---

## Zona de aterrissagem no GCS

O dataset é passado como arquivo `.parquet`no Google Cloud Storage antes da Bronze, para permitir processamento fora do BigQuery.

**Bucket:** `gs://${BUCKET}` na região `${LOCATION}`, ambos definidos em [`config.env`](../config.env.example) e criados por [`setup/00-create-bucket.sh`](../setup/00-create-bucket.sh).

| Prefixo | Conteúdo |
|---|---|
| `blocks/` | Blocos de 2020, todas as colunas |
| `transactions/` | Transações de 2020, todas as colunas |
| `tx_pre2020_ref/` | Três colunas de todas as transações anteriores a 2020 |

**Formato:** Parquet com compressão ZSTD.

Parquet foi escolhido por ser o padrão de fato para dados analíticos, com leitura nativa em pandas, PyArrow, Spark e DuckDB. ZSTD comprime melhor que Snappy com desempenho de descompressão comparável, e como os arquivos são lidos essencialmente uma vez, o tamanho pesa mais que a velocidade.

**Nota sobre circularidade.** A fonte é um dataset nativo do BigQuery, sem distribuição em arquivo. O fluxo exporta do BigQuery para o GCS e recarrega para o BigQuery, o que é circular. A justificativa é reproduzir o padrão arquitetural de zona de aterrissagem que existiria caso a origem fosse um sistema externo entregando arquivos, além de habilitar o processamento externo ao BigQuery.

---

## Tabelas produzidas

### `bronze.blocks`

Uma linha por bloco. Todas as colunas da origem preservadas, incluindo `coinbase_param`, `merkle_root`, `nonce` e `bits`.

```
PARTITION BY DATE(timestamp)
CLUSTER BY number
require_partition_filter = TRUE
```

Particionada por dia porque a poda fica trinta vezes mais fina que por mês. São 366 partições, bem dentro do limite de 4.000 do BigQuery.

Clusterizada por `number` para consultas por faixa de blocos.

**Volume:** 53.222 linhas (blocos 610.691 a 663.912).

### `bronze.transactions`

Uma linha por transação, com as arrays `inputs` e `outputs` aninhadas.

```
PARTITION BY DATE(block_timestamp)
CLUSTER BY hash
require_partition_filter = TRUE
```

Clusterizada por `hash` porque essa é a coluna do join mais caro do pipeline, o cruzamento com `spent_transaction_hash` para calcular idade de moeda.

**Volume:** 112.553.498 linhas, das quais 53.222 são coinbase.

### `bronze.tx_pre2020_ref`

Tabela de referência com o mapeamento entre hash de transação e timestamp de criação, para todas as transações anteriores a 01/01/2020.

```
CLUSTER BY hash
```

Sem particionamento por tempo, de propósito: ela é acessada exclusivamente por `hash`, nunca por data. Particionar criaria milhares de partições minúsculas e prejudicaria o join.

Contém apenas três colunas de negócio (`hash`, `block_timestamp`, `block_number`), então é a única tabela da camada em que há seleção de colunas na origem. Isso é coerente porque ela não é cópia de dado bruto: é uma tabela derivada, construída para um propósito específico.

---

## O problema do encapsulamento LIST

Ao exportar para Parquet e recarregar, as colunas `inputs` e `outputs` retornam com um tipo deformado:

```
STRUCT<list ARRAY<STRUCT<element STRUCT<index INT64, ...>>>>
```

em vez do esperado:

```
ARRAY<STRUCT<index INT64, ...>>
```

Isso não é corrupção. A especificação do Parquet grava listas como um grupo `list` contendo elementos `element`, e o BigQuery expõe essa estrutura interna literalmente quando a inferência de lista não é aplicada na carga.

A maioria das ferramentas fora do BigQuery (pandas, PyArrow, Spark, DuckDB) reconhece o padrão automaticamente, então os arquivos no bucket permanecem plenamente utilizáveis.

Dentro do BigQuery, a solução adotada foi **reconstruir as arrays em SQL** na criação da tabela Bronze:

```sql
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
) AS outputs
```

Note que `addresses` também está encapsulado e exige o mesmo tratamento em um nível adicional. A ordem dos campos dentro do `SELECT AS STRUCT` reproduz exatamente o schema da origem.

Como consequência positiva, a reconstrução exige um `CREATE TABLE AS SELECT`, o que permite adicionar os metadados de ingestão na mesma operação, evitando um `UPDATE` em 112 milhões de linhas.

---

## Decisões e justificativas

### Manter `script_asm` e `script_hex`

Medição experimental sobre junho de 2020:

| Versão | Tamanho do mês | Extrapolação anual |
|---|---:|---:|
| Com os campos de script | 16,81 GB | ~202 GB |
| Sem os campos de script | 7,70 GB | ~92 GB |

A diferença de aproximadamente 110 GB representa cerca de 2 dólares mensais de armazenamento. Manter preserva a fidelidade da camada e é reforçado por um fato técnico: o BigQuery poda campos aninhados na leitura, então colunas nunca selecionadas não entram no custo de consulta. O custo é fixo e pequeno, não recorrente.

### Particionamento diário em vez de mensal

Trinta vezes mais poda nas análises por data, ao custo de 366 partições em vez de 12. Bem dentro do limite de 4.000.

### `require_partition_filter = TRUE`

Faz o BigQuery **rejeitar** qualquer consulta sem filtro de data, em vez de executá-la varrendo a tabela inteira. A consulta falha antes de processar, então não custa nada.

### Recorte anual em vez da chain completa

A ingestão da chain completa tem em torno de 1,42 bilhão de transações (2,37 TB). Além do custo de armazenamento, cada consulta teria custo elevado.

O recorte de 2020 lê 219,7 GB, cerca de **11 vezes menos**, e o particionamento garante que consultas subsequentes custem centavos.

---

## Metadados e rastreabilidade

Cada linha carrega duas colunas técnicas:

| Coluna | Conteúdo |
|---|---|
| `_batch_id` | Identificador do lote de ingestão, formato `AAAAMMDD-bronze-vN` |
| `_ingested_at` | Timestamp UTC da carga, avaliado uma vez por consulta |

O `_batch_id` é um identificador opaco. Ele não precisa ser uma data correta, precisa ser único e consistente. O timestamp real da execução fica em `_ingested_at`.

Custo de armazenamento: desprezível. O BigQuery é colunar e comprime valores constantes repetidos para praticamente zero.

---

## Validação

| Verificação | Valor esperado |
|---|---:|
| Total de blocos | 53.222 |
| Bloco mínimo / máximo | 610.691 / 663.912 |
| Total de transações | 112.553.498 |
| Transações coinbase | 53.222 |
| Blocos distintos em `transactions` | 53.222 |
| Período | 2020-01-01 a 2020-12-31 |
| `ARRAY_LENGTH(inputs) <> input_count` | 0 |
| `ARRAY_LENGTH(outputs) <> output_count` | 0 |

As duas últimas são as mais importantes: confirmam que a reconstrução das arrays preservou todos os elementos.

A soma de `transaction_count` em `bronze.blocks` deve dar exatamente 112.553.498, servindo como gabarito independente para validar a tabela de transações.

---

## Ordem de execução

| Script | Descrição | Limite de bytes |
|---|---|---|
| `02-export-blocks-to-gcs.sql` | Exporta blocos para o GCS | padrão |
| `03-export-transactions-to-gcs.sql` | Exporta transações para o GCS | **250 GB** |
| `04-export-references-pre-2020-to-gcs.sql` | Exporta referência pré-2020 | **60 GB** |
| `05-load-gcs-staging.sql` | Carrega do GCS para staging (gratuito) | padrão |
| `06-create-blocks-table.sql` | Cria `bronze.blocks` | padrão |
| `07-create-transactions-table.sql` | Cria `bronze.transactions` com reconstrução | padrão |
| `08-create-references-pre-2020-table.sql` | Cria a tabela de referência | padrão |
| `09-validate-blocks.sql` | Validação | padrão |
| `10-validate-transactions.sql` | Validação | padrão |
| `11-clean-staging-tables.sql` | Remove as tabelas de staging | padrão |

**Confirme no console que os arquivos apareceram no bucket** antes de executar o passo 05.

**Não pule o passo 11.** As tabelas de staging duplicam 220 GB e custam armazenamento sem servir a nenhum propósito depois que a Bronze está construída. A zona de aterrissagem real são os arquivos no GCS.
