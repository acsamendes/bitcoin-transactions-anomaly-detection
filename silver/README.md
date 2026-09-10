# Camada Silver

Dados desaninhados, limpos e enriquecidos. É aqui que o trabalho pesado acontece: mudança de granularidade, resolução do grafo de gastos e cálculo do contexto de rede.

---

## Sumário

- [Princípio da camada](#princípio-da-camada)
- [Tabelas produzidas](#tabelas-produzidas)
- [Achados que moldaram a camada](#achados-que-moldaram-a-camada)
- [A otimização do cálculo de idade](#a-otimização-do-cálculo-de-idade)
- [Decisões de modelagem](#decisões-de-modelagem)
- [Metadados e rastreabilidade](#metadados-e-rastreabilidade)
- [Validação](#validação)
- [Ordem de execução](#ordem-de-execução)

---

## Princípio da camada

Silver entrega dados granulares e confiáveis, prontos para serem consumidos por qualquer análise. Ela não decide o que é feature nem prepara nada para um modelo específico: isso é responsabilidade da Gold.

O que a camada faz:

- Desaninha as arrays em tabelas relacionais
- Descarta campos sem uso analítico (`script_asm`, `script_hex`)
- Resolve o grafo de gastos entre transações
- Calcula a idade dos UTXOs consumidos
- Agrega o estado da rede por hora
- Consolida tudo em uma linha por transação

O que a camada **não** faz:

- Não cria razões nem normalizações (isso é Gold)
- Não aplica escalonamento (isso pertence ao modelo)
- Não filtra transações por relevância para modelagem

---

## Tabelas produzidas

### `silver.tx_outputs`

Uma linha por output. Resultado de `UNNEST(t.outputs)` sobre a Bronze.

```
PARTITION BY DATE(block_timestamp)
CLUSTER BY transaction_hash
```

**Volume:** 303.543.237 linhas.

Colunas relevantes: `transaction_hash`, `output_index`, `value_satoshi`, `script_type`, `required_signatures`, `address_count`, `address_single`, `addresses`.

O campo `is_coinbase` é trazido desnormalizado da transação, evitando um join em toda análise.

### `silver.tx_inputs`

Uma linha por input. Resultado de `UNNEST(t.inputs)`.

```
PARTITION BY DATE(block_timestamp)
CLUSTER BY spent_transaction_hash
```

**Volume:** 291.558.501 linhas.

O clustering é por `spent_transaction_hash`, **não** por `transaction_hash`. Essa é a coluna que participa do join mais caro do pipeline (o cruzamento com o índice de origem para calcular idade de moeda), e é ela que manda na escolha.

Além dos campos análogos aos de outputs, traz `spent_transaction_hash`, `spent_output_index`, `sequence` e `rbf_signaled`.

### `silver.tx_origin_index`

Índice unificado que mapeia hash de transação para o timestamp e o bloco de criação. Une os hashes de 2020 (vindos de `bronze.transactions`) com os anteriores (de `bronze.tx_pre2020_ref`).

```
CLUSTER BY hash
```

**Volume:** 601.576.446 linhas, 45,94 GB.

Sem particionamento, porque é acessado exclusivamente por `hash`.

Esta tabela existe puramente por razões de custo. Ver a seção [A otimização do cálculo de idade](#a-otimização-do-cálculo-de-idade).

### `silver.coin_age`

Uma linha por input não coinbase, com a idade da moeda consumida.

```
PARTITION BY DATE(block_timestamp)
CLUSTER BY transaction_hash
```

Calcula a idade em três unidades:

| Coluna | Por que existe |
|---|---|
| `idade_horas` | Capta movimentação rápida, típica de automação e serviços |
| `idade_dias` | Escala natural para dormência |
| `idade_blocos` | Imune a manipulação de timestamp por mineradores |

Também traz `origem_nao_resolvida` como flag explícita, em vez de deixar nulo silencioso. Na execução validada, o valor foi zero, confirmando que a tabela de referência cobre todos os casos.

O clustering aqui é por `transaction_hash` porque a agregação é por transação, não mais por hash de origem.

### `silver.network_context_hourly`

Estado agregado da rede por hora UTC. Uma linha por hora cheia.

```
PARTITION BY DATE(hora)
CLUSTER BY hora
```

**Volume:** aproximadamente 8.784 linhas (366 dias x 24 horas).

Colunas principais: `blocos_na_hora`, `ocupacao_media`, `fee_vbyte_mediana`, `fee_vbyte_p90`, `tx_total_hora`.

**Por que a granularidade é horária e não por bloco.** Um bloco individual pode ter poucas transações e mediana instável. A hora agrega em torno de seis blocos e produz um sinal mais estável, sem perder a variação intradiária que uma agregação diária apagaria.

**Por que mediana e não média.** A distribuição de taxa tem cauda pesadíssima (mediana de 34,5 sat/vB contra máximo de 1.837.260). Uma única transação extrema distorce a média inteira. `APPROX_QUANTILES` calcula os percentis de forma aproximada e muito mais barata que o exato.

**Por que excluir coinbase.** Coinbase não tem taxa no sentido normal e contaminaria a mediana.

**Para que serve.** Sem essa tabela, o modelo marcaria todo o dia 12 de março de 2020 como anômalo, porque a mediana de taxa explodiu no crash da COVID. Isso é evento de rede, não comportamento suspeito. A normalização transforma a feature de "taxa de 50 sat/vB" em "taxa 6 vezes acima da mediana da hora", que é o que carrega sinal.

### `silver.tx_enriched`

Uma linha por transação, consolidando os escalares da Bronze com agregações de outputs, inputs e idade de moeda.

```
PARTITION BY DATE(block_timestamp)
CLUSTER BY transaction_hash
```

**Volume:** 112.553.498 linhas, incluindo as 53.222 coinbase.

É a última tabela da camada e a base direta da Gold.

---

## Achados que moldaram a camada

### Coinbase não tem inputs

Ao validar o desaninhamento, `tx_inputs` retornou 112.500.276 transações distintas contra 112.553.498 em `tx_outputs`. A diferença de exatamente 53.222 é o número de blocos.

A conclusão é que transações coinbase têm array de inputs **vazia**, e `UNNEST` de array vazia produz zero linhas. Elas simplesmente não aparecem em `tx_inputs`.

**Consequência no desenho:** `tx_enriched` usa `bronze.transactions` como base com `LEFT JOIN` para os agregados. Com `INNER JOIN`, as 53.222 coinbase desapareceriam silenciosamente. Com `LEFT JOIN`, elas aparecem com `n_inputs` nulo, presentes e identificáveis.

### O limiar de dust

A definição de dust no Bitcoin Core é econômica: um output é dust quando gastá-lo custaria mais em taxa do que ele vale. O valor depende do tipo de script e da taxa de referência, então não é constante.

Adotou-se **546 satoshis**, referência do Bitcoin Core para outputs P2PKH, excluindo os zerados, que são fenômeno distinto.

---

## A otimização do cálculo de idade

Esta é a otimização mais significativa do pipeline.

### O problema

O cálculo de idade exige cruzar `tx_inputs.spent_transaction_hash` contra o timestamp da transação que criou a moeda. Esse timestamp pode estar em dois lugares: em `bronze.transactions` (moeda de 2020) ou em `bronze.tx_pre2020_ref` (moeda anterior).

A primeira implementação uniu as duas fontes num CTE:

```sql
WITH origem AS (
  SELECT hash, block_timestamp, block_number FROM bronze.transactions WHERE ...
  UNION ALL
  SELECT hash, block_timestamp, block_number FROM bronze.tx_pre2020_ref
)
SELECT ... FROM silver.tx_inputs i LEFT JOIN origem o ON ...
```

Teste com **um único dia**: 41,51 GB processados. Extrapolando para o ano: aproximadamente **15 TB**, ou cerca de 95 dólares.

### A causa

O CTE reconstrói a união inteira a cada execução. O filtro nos inputs (um dia) não propaga para o lado direito do join, então as duas fontes são lidas integralmente todas as vezes. O clustering por `hash` não ajuda, porque ele acelera busca por valor específico, não a construção de uma tabela completa.

### A solução

Materializar a união **uma vez** como tabela física estreita, com apenas as três colunas necessárias:

```sql
CREATE OR REPLACE TABLE silver.tx_origin_index
CLUSTER BY hash AS
SELECT hash, block_timestamp, block_number FROM bronze.transactions WHERE ...
UNION ALL
SELECT hash, block_timestamp, block_number FROM bronze.tx_pre2020_ref;
```

Resultado: 601.576.446 linhas em 45,94 GB. O `coin_age` do ano inteiro passou a custar menos de 100 GB.

### O ganho

| | Antes | Depois |
|---|---:|---:|
| Processamento do ano | ~15 TB | < 100 GB |
| Custo estimado | ~95 USD | < 1 USD |
| Redução | | **~150x** |

---

## Decisões de modelagem

### Descarte de `script_asm` e `script_hex`

Ao contrário da Bronze, aqui o descarte é apropriado. Silver é a camada de transformação com propósito, e esses campos não entram em nenhuma feature planejada. A Bronze permanece fiel, então nada se perde.

### `STDDEV_POP` em vez de `STDDEV`

`STDDEV` é o desvio amostral e exige pelo menos duas linhas, retornando nulo para transações de output único, que são comuns. `STDDEV_POP` retorna zero nesse caso.

### `LOGICAL_OR` para RBF

A regra do BIP125 é por transação: basta um input sinalizar para que a transação inteira seja substituível. A agregação correta é `LOGICAL_OR(rbf_signaled)`, não média nem contagem.

A sinalização por input usa `sequence < 0xFFFFFFFE`. O valor é o máximo de um inteiro de 32 bits menos um. Vale registrar que a semântica de `sequence` tem interações com o BIP68 (timelocks relativos), então a detecção deve ser descrita como aproximada.

### Contagem de endereços distintos

`COUNT(DISTINCT address_single)` ignora nulos, e como `address_single` só é preenchido quando há exatamente um endereço, inputs multisig sumiriam da contagem. Foram mantidas duas colunas complementares: `in_enderecos_unicos_distintos` e `in_sem_endereco_unico`, de modo que ambos os números sejam interpretáveis.

---

## Metadados e rastreabilidade

As tabelas desaninhadas diretamente da Bronze, `tx_outputs` e `tx_inputs`,
carregam três colunas técnicas:

| Coluna | Responde |
|---|---|
| `_source_batch_id` | De qual carga Bronze veio este dado |
| `_batch_id` | Qual execução Silver gerou esta linha |
| `_processed_at` | Quando essa execução rodou |

As demais (`tx_origin_index`, `coin_age`, `network_context_hourly` e `tx_enriched`)
carregam apenas as duas últimas. Elas derivam de tabelas Silver que já registram a
procedência da Bronze, então repetir `_source_batch_id` seria propagar uma coluna
redundante por centenas de milhões de linhas.

A distinção importa porque Silver é a camada mais reprocessada, justamente por ser onde a lógica mora. Sem `_batch_id` próprio, um reprocessamento seria indistinguível do anterior.

---

## Validação

### Desaninhamento

| Verificação | Esperado |
|---|---:|
| Transações distintas em `tx_outputs` | 112.553.498 |
| Transações distintas em `tx_inputs` | 112.500.276 |
| Diferença entre as duas | 53.222 (as coinbase) |
| Linhas em `tx_outputs` | 303.543.237 |
| Linhas em `tx_inputs` | 291.558.501 |

### `tx_enriched`

| Verificação | Esperado |
|---|---:|
| Total | 112.553.498 |
| Coinbase | 53.222 |
| Sem agregação de inputs | 53.222 (só as coinbase) |
| Erro de join em inputs | 0 |
| Divergência `n_outputs` vs `output_count` | 0 |
| Divergência `n_inputs` vs `input_count` | 0 |
| Desvio padrão nulo | 0 |
| Taxa negativa (impossível) | 0 |
| Outputs maiores que inputs (impossível) | 0 |
| Origem de moeda não resolvida | 0 |

As três últimas são testes de sanidade do protocolo: qualquer valor diferente de zero indica bug.

### Densidade das features

Nenhuma feature pode ser sempre zero, sob pena de ser inútil no modelo. Valores obtidos:

| Feature | Transações com valor positivo |
|---|---:|
| `out_valor_zero` | 7.843.477 |
| `out_dust` | 128.609 |
| `out_nonstandard` | 7.853.912 |
| `out_segwit` | 24.758.108 |
| `in_segwit` | 21.410.747 |
| `rbf_signaled` | 13.004.620 |
| Candidatas a CoinJoin | 43.619 |
| Moeda acima de 5 anos | 27.505 |

---

## Ordem de execução

A ordem importa: existem dependências reais.

| Script | Depende de |
|---|---|
| `12-create-outputs-table.sql` | `bronze.transactions` |
| `13-create-inputs-table.sql` | `bronze.transactions` |
| `14-create-transactions-index.sql` | `bronze.transactions`, `bronze.tx_pre2020_ref` |
| `15-create-coin-age-table.sql` | `tx_inputs` (13) e `tx_origin_index` (14) |
| `16-create-network-context-per-hour-table.sql` | `bronze.blocks`, `bronze.transactions` |
| `17-create-enriched-table.sql` | `tx_outputs`, `tx_inputs`, `coin_age` |
| `18-validate-inputs-outputs.sql` | 12 e 13 |
| `19-validate-enriched-table.sql` | 17 |

O script 17 é o mais pesado da camada: três agregações grandes mais três joins.
