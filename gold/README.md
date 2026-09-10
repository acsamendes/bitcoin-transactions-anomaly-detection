# Camada Gold

Dados agregados e prontos para consumo. Aqui a fidelidade cede lugar à utilidade: contagens viram razões, valores viram logaritmos, e a taxa é normalizada pelo contexto da rede.

---

## Sumário

- [Princípio da camada](#princípio-da-camada)
- [Tabelas produzidas](#tabelas-produzidas)
- [Princípios de construção das features](#princípios-de-construção-das-features)
- [O processo iterativo de ajuste](#o-processo-iterativo-de-ajuste)
- [Resultados da detecção](#resultados-da-detecção)
- [Priorização e análise de sensibilidade](#priorização-e-análise-de-sensibilidade)
- [Validação](#validação)
- [Ordem de execução](#ordem-de-execução)

---

## Princípio da camada

Silver entrega dados limpos e granulares. Gold entrega dados modelados para um objetivo.

O que a camada faz:

- Converte contagens absolutas em razões, para comparabilidade entre escalas
- Aplica transformação logarítmica onde a distribuição tem cauda pesada
- Normaliza a taxa pelo contexto de rede da hora
- Substitui nulos por valores neutros
- Exclui a população estruturalmente distinta (coinbase)
- Materializa os scores produzidos pelo modelo e a classificação de prioridade

O que a camada **não** faz:

- Não treina nem avalia modelos, o que pertence à camada Model
- Não aplica escalonamento, o que é responsabilidade do próprio `CREATE MODEL`

---

## Tabelas produzidas

### `gold.tx_features`

Matriz de 21 features, uma linha por transação não coinbase.

```
PARTITION BY DATE(block_timestamp)
CLUSTER BY transaction_hash
require_partition_filter = TRUE
```

**Volume:** 112.500.276 linhas (112.553.498 menos as 53.222 coinbase).

Além das features, mantém `transaction_hash`, `block_timestamp` e `block_number` como identificadores, excluídos do treino via `SELECT * EXCEPT (...)`.

A descrição de cada feature está em [`docs/FEATURES.md`](../../docs/FEATURES.md).

### `gold.anomaly_scores`

Uma linha por transação, com o resultado de `ML.DETECT_ANOMALIES`.

```
PARTITION BY DATE(block_timestamp)
CLUSTER BY transaction_hash
require_partition_filter = TRUE
```

Colunas: `transaction_hash`, `block_timestamp`, `block_number`, `is_anomaly`, `normalized_distance`, `centroid_id`.

As 21 features **não** são replicadas aqui, embora `ML.DETECT_ANOMALIES` as retorne. Elas já existem em `tx_features` e são recuperáveis por join, então duplicá-las em 112,5 milhões de linhas seria desperdício.

Detalhe de implementação: como `tx_features` já possui `_batch_id` e `_processed_at`, e a criação da tabela adiciona os seus, os nomes colidiriam. Daí o `SELECT * EXCEPT (_batch_id, _processed_at)` na subconsulta de entrada.

### `gold.v_anomaly_priority`

View que classifica as transações em faixas de prioridade a partir do score contínuo.

```sql
CASE
  WHEN normalized_distance >= 3.0   THEN 'alta'
  WHEN normalized_distance >= 2.241 THEN 'media'
  WHEN normalized_distance >= 1.685 THEN 'baixa'
  ELSE 'normal'
END
```

Os limiares 1,685 e 2,241 correspondem aos percentis 99 e 99,9 medidos na distribuição de distâncias.

É view e não tabela porque a prioridade é inteiramente derivada de `normalized_distance`, que já está materializado. Criar tabela duplicaria dado sem adicionar informação, e recriar via `ML.DETECT_ANOMALIES` ou via `UPDATE` custaria uma varredura completa.

---

## Princípios de construção das features

### Razões em vez de valores absolutos

O modelo aprende melhor com "o maior output representa 95% do total" do que com "o maior output é 4.383.533.113.612 satoshis". Razões são comparáveis entre transações de escalas radicalmente diferentes.

Uma transação com 3 outputs dust em 5 tem comportamento muito diferente de outra com 3 em 800, mas a contagem absoluta é idêntica. A razão captura a intenção; a escala já está em outra feature.

### Transformação logarítmica

A distribuição de valores em Bitcoin tem cauda pesadíssima. Sem log, o K-Means encontraria basicamente "a transação mais cara do ano" e ignoraria as outras 20 dimensões.

O `+1` antes do log evita indefinição em zero.

### Normalização pelo contexto de rede

A feature não é a taxa, é o quanto ela desvia da mediana daquela hora. Uma taxa de 50 sat/vB não diz nada isolada: se a mediana da hora era 8, é urgência anômala; se era 45, é normal.

Sem isso, o modelo marcaria todo o dia 12 de março de 2020 como anômalo por causa do congestionamento da COVID, o que é evento de rede e não comportamento suspeito.

### Blindagem contra nulos

Todas as divisões usam `SAFE_DIVIDE` envolto em `IFNULL` com valor neutro. O motivo é que o `CREATE MODEL` **descarta linhas com nulo**, e sem a blindagem essas transações sumiriam do treino silenciosamente.

Os valores de fallback são semanticamente neutros: `1` para razões que representam "conforme o esperado", `0` para proporções em que ausência significa ausência.

### Exclusão das transações coinbase

Coinbase não consome UTXO nenhum, então metade das features seria indefinida: `n_inputs` zero, todas as cinco de idade indeterminadas, taxa sem sentido.

Se mantidas, o K-Means gastaria um dos 8 clusters para agrupar 53.222 transações quase idênticas, sobrando 7 para os 112,5 milhões restantes. E elas apareceriam como anômalas em qualquer score, poluindo o ranking sem informar nada, já que são identificáveis por `WHERE is_coinbase`.

Elas permanecem em `silver.tx_enriched` e podem ser analisadas separadamente.

---

## O processo iterativo de ajuste

A matriz não saiu pronta. Foi construída, medida e corrigida em três rodadas, e esse processo é parte do resultado.

### Critério de diagnóstico

Duas métricas por feature:

| Métrica | Significado | Limite adotado |
|---|---|---|
| Coeficiente de variação | desvio / média | acima de 4 sugere dispersão excessiva |
| Desvios até o máximo | (máx - média) / desvio | acima de 50 indica cauda pesada |

A segunda é a mais direta. Uma feature com 93 desvios até o máximo significa que uma única transação, após padronização, contribuiria com 8.649 para a distância ao quadrado, enquanto uma feature bem comportada contribui entre 1 e 9. Ela dominaria o modelo sozinha.

### Rodada 1: caudas pesadas nas contagens

| Feature | Desvios até o máximo |
|---|---:|
| `f_n_inputs` | 93 |
| `f_n_outputs` | ~86 |
| `f_taxa_relativa` | ~48 |

Correção: log em `n_inputs`, `n_outputs`, `razao_in_out`, `taxa_relativa` e `dispersao_idade`.

Após a correção, `f_log_n_inputs` passou a ter desvio 0,50 sobre média 0,90, contra 15,75 sobre 2,59 antes.

### Rodada 2: feature sem variância

`f_razao_dust` apresentou média 0,0004 e desvio 0,012. Praticamente zero em todo o dataset, o que após padronização vira ruído sem poder discriminativo. Removida.

Na mesma rodada, `f_razao_valores_distintos` apresentou média 0,997 e desvio 0,039. Correto (99,7% das transações têm outputs de valores distintos), mas contribuiria pouco. Invertida para `f_repeticao_valores`, onde 0 é o caso normal, mais uma binária `f_padrao_mistura`.

### Rodada 3: última cauda

`f_cv_outputs` apresentou 83,5 desvios até o máximo, com valor extremo de 51,7. Log aplicado, resultando em `f_log_cv_outputs` com 10,9 desvios.

### Resultado final

As 21 features passaram no critério. Nenhuma domina o cálculo de distância e nenhuma é constante.

Três features aparecem com coeficiente de variação alto e são aceitáveis: `f_padrao_mistura`, `f_repeticao_valores` e `f_razao_moeda_antiga`. O CV alto decorre da raridade do fenômeno, não de cauda pesada, e como são limitadas entre 0 e 1, não distorcem escala.

---

## Resultados da detecção

| Métrica | Valor |
|---|---:|
| Transações avaliadas | 112.500.276 |
| Marcadas como anomalia | 1.119.290 |
| Percentual | 0,995% |
| Clusters utilizados | 8 |
| Scores nulos | 0 |

O percentual bate com o `contamination` de 0,01 configurado.

### Distribuição das distâncias

| Percentil | Distância normalizada |
|---|---:|
| p50 | 0,847 |
| p90 | 1,187 |
| p95 | 1,347 |
| p99 | 1,685 |
| p99,9 | 2,241 |
| Máximo | 5,256 |

Apenas 9 transações no ano inteiro ultrapassam distância 5, e nenhuma ultrapassa 10.

**A distribuição não apresenta quebra natural.** A transição do p99 ao máximo é suave, então o corte de 1% permanece uma convenção do analista, não uma descoberta empírica. Isso é declarado explicitamente.

---

## Priorização e análise de sensibilidade

### O que o `contamination` é e não é

Ele define a **fração do dataset declarada como anômala**. Com 0,01, o modelo ordena por distância ao centroide mais próximo, pega o percentil 99, e marca tudo acima.

Ele **não descobre nada**. É um corte imposto pelo analista. Com 0,05 marcaria 5%, e as mesmas transações continuariam nas mesmas posições do ranking.

O que o modelo produz é o `normalized_distance`, contínuo. Por isso essa coluna é preservada: permite reavaliação com qualquer limiar sem retreinar nem reprocessar.

### Cortes avaliados

| Corte | Limiar | Transações | Perfil |
|---|---:|---:|---|
| 1% (p99) | 1,685 | 1.128.344 | Recall alto, inviável para revisão |
| 0,1% (p99,9) | 2,241 | 115.560 | Intermediário |
| Distância >= 3,0 | 3,000 | 12.472 | Filtra o incomum trivial |

O corte em 3,0 é qualitativamente distinto: elimina os clusters dominados por transações de valor zero (todos abaixo de distância 2,0) e preserva consolidação massiva e moeda dormente, resultando em conjunto de tamanho investigável.

### Sobre falsos positivos

Não existem falsos positivos no sentido estrito, porque não há rótulo. Uma consolidação de exchange não é erro do modelo: ela é genuinamente atípica. O que ela não é, é suspeita.

O problema não é de precisão, é de **priorização**. A entrega é um ranking, não uma classificação binária, e o corte é função do orçamento de investigação disponível.

---

## Validação

### `tx_features`

| Verificação | Esperado |
|---|---:|
| Total de linhas | 112.500.276 |
| Nulos em qualquer feature | 0 |
| NaN em `f_log_cv_outputs` | 0 |
| Infinito em `f_log_taxa_relativa` | 0 |

Nulos são críticos: o `CREATE MODEL` descarta essas linhas silenciosamente.

### `anomaly_scores`

| Verificação | Esperado |
|---|---:|
| Total de linhas | 112.500.276 |
| Percentual marcado como anomalia | ~1,0 |
| Clusters distintos usados | 8 |
| Score nulo | 0 |

---

## Ordem de execução

| Nº | Consulta | Descrição |
|---:|---|---|
| 20 | Criação - Matriz de Features | Constrói `tx_features` |
| 21 | Validação - Matriz de Features | Verificação de nulos |
| 22 | Análise - Variância das Features | Diagnóstico de cauda e variância |
| | | *(23 a 27: camada Model)* |
| 28 | Criação - Scores de Anomalia | Inferência sobre a base completa |
| 29 | Validação - Scores de Anomalia | Verificação |
| 30 | Análise - Distribuição de Distâncias | Percentis e escolha do corte |
| | | *(31: camada Model)* |
| 32 | Análise - Top Anomalias | Ranking para inspeção manual |
| 33 | Criação - View com Prioridades | Cria `v_anomaly_priority` |
| 34 | Análise - Prioridades pela View | Contagem por faixa |

Execute a consulta 22 **antes** de treinar. Foi ela que revelou as caudas pesadas e a feature sem variância.

A consulta 28 é a mais cara da camada, aplicando o modelo sobre 112,5 milhões de linhas.

### Sobre a numeração intercalada

As consultas 23 a 27 e 31 pertencem à camada Model e ficam intercaladas na numeração porque a ordem reflete a **sequência de execução**, não o agrupamento lógico. A camada Model precisa dos modelos treinados (23 a 27) antes que a Gold possa gerar os scores (28), e a avaliação de concordância (31) precisa dos scores prontos.
