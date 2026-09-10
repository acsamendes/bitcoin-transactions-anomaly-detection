# Camada Gold

Dados modelados para um propósito específico: alimentar o K-Means e produzir scores de anomalia. Aqui a fidelidade cede lugar à utilidade para o modelo.

---

## Sumário

- [Princípio da camada](#princípio-da-camada)
- [Tabelas e modelos](#tabelas-e-modelos)
- [Princípios de construção das features](#princípios-de-construção-das-features)
- [O processo iterativo de ajuste](#o-processo-iterativo-de-ajuste)
- [Escolha do modelo](#escolha-do-modelo)
- [Detecção de anomalias](#detecção-de-anomalias)
- [Estratégia de avaliação sem rótulos](#estratégia-de-avaliação-sem-rótulos)
- [Validação](#validação)
- [Ordem de execução](#ordem-de-execução)
- [Status](#status)

---

## Princípio da camada

Silver entrega dados limpos e granulares. Gold entrega dados modelados para um objetivo.

O que a camada faz:

- Converte contagens absolutas em razões, para comparabilidade entre escalas
- Aplica transformação logarítmica onde a distribuição tem cauda pesada
- Normaliza a taxa pelo contexto de rede da hora
- Substitui nulos por valores neutros
- Exclui a população estruturalmente distinta (coinbase)
- Treina e aplica o modelo

---

## Tabelas e modelos

### `gold.tx_features`

Matriz de 21 features, uma linha por transação não coinbase.

```
PARTITION BY DATE(block_timestamp)
CLUSTER BY transaction_hash
require_partition_filter = TRUE
```

**Volume:** 112.500.276 linhas (112.553.498 menos as 53.222 coinbase).

Além das features, mantém `transaction_hash`, `block_timestamp` e `block_number` como identificadores, excluídos do treino com `SELECT * EXCEPT (...)`. A descrição completa de cada feature está em [`docs/FEATURES.md`](../docs/FEATURES.md).

### Modelos K-Means

| Modelo | K | Amostra de treino |
|---|---:|---|
| `kmeans_k3` | 3 | 1% |
| `kmeans_k5` | 5 | 1% |
| `kmeans_k6` | 6 | 1% |
| `kmeans_k8` | 8 | 1% |
| `kmeans_k12` | 12 | 1% |
| `kmeans_k8_10pct` | 8 | 10% |
| `kmeans_k8_full` | 8 | 100% |

Configuração comum:

```sql
OPTIONS (
  model_type = 'KMEANS',
  num_clusters = K,
  standardize_features = TRUE,
  kmeans_init_method = 'KMEANS++',
  max_iterations = 30
)
```

`standardize_features = TRUE` aplica z-score em cada feature. Sem isso, `f_log_valor_total` (média 15,5) dominaria as binárias (média entre 0 e 1).

`KMEANS++` escolhe os centroides iniciais de forma informada em vez de aleatória, melhorando a convergência.

`max_iterations = 30` é folgado: os modelos convergiram em 5 a 6 iterações.

### `gold.anomaly_scores`

Uma linha por transação, com o resultado de `ML.DETECT_ANOMALIES`.

```
PARTITION BY DATE(block_timestamp)
CLUSTER BY transaction_hash
require_partition_filter = TRUE
```

Colunas: `transaction_hash`, `block_timestamp`, `block_number`, `is_anomaly`, `normalized_distance`, `centroid_id`.

As 21 features **não** são replicadas aqui, embora `ML.DETECT_ANOMALIES` as retorne. Elas já existem em `tx_features` e podem ser recuperadas por join, então replicá-las em 112,5 milhões de linhas seria desperdício.

---

## Princípios de construção das features

### Amostragem determinística

O treino usa uma amostra selecionada por hash, não por sorteio:

```sql
AND MOD(ABS(FARM_FINGERPRINT(transaction_hash)), 100) = 0
```

`FARM_FINGERPRINT` gera um inteiro determinístico a partir do hash. O `MOD(..., 100) = 0` seleciona aproximadamente 1 em cada 100, e como o hash de uma transação Bitcoin é essencialmente aleatório, a distribuição dos restos é uniforme.

Duas vantagens sobre `RAND() < 0.01`: os modelos comparados veem exatamente as mesmas linhas, de modo que a diferença nas métricas vem do K e não da amostra; e o experimento é reproduzível.

Para 10%, o divisor vira 10. Como a lógica é a mesma, a amostra de 10% **contém** a de 1%, o que torna a comparação entre elas ainda mais limpa.

### Razões em vez de valores absolutos

O modelo aprende melhor com "o maior output representa 95% do total" do que com "o maior output é 4.383.533.113.612 satoshis". Razões são comparáveis entre transações de escalas radicalmente diferentes.

Uma transação com 3 outputs dust em 5 tem comportamento muito diferente de outra com 3 em 800, mas a contagem absoluta é idêntica. A razão captura a intenção; a escala já está em outra feature.

### Transformação logarítmica

A distribuição de valores em Bitcoin tem cauda pesadíssima. Sem log, o K-Means encontraria basicamente "a transação mais cara do ano" e ignoraria as outras 20 dimensões.

O `+1` antes do log evita indefinição em zero.

### Normalização pelo contexto de rede

A feature não é a taxa, é o quanto ela desvia da mediana daquela hora. Uma taxa de 50 sat/vB não diz nada isolada: se a mediana da hora era 8, é urgência anômala; se era 45, é normal.

### Blindagem contra nulos

Todas as divisões usam `SAFE_DIVIDE` envolto em `IFNULL` com valor neutro. O motivo é que o `CREATE MODEL` do BigQuery ML **descarta linhas com nulo**, e sem a blindagem essas transações sumiriam do treino silenciosamente.

Os valores de fallback são semanticamente neutros: `1` para razões que representam "conforme o esperado", `0` para proporções em que ausência significa ausência.

### Exclusão das transações coinbase

Coinbase não consome UTXO nenhum, então metade das features seria indefinida para elas: `n_inputs` zero, todas as cinco de idade de moeda indeterminadas, taxa sem sentido.

Se mantidas, o K-Means gastaria um dos 8 clusters para agrupar 53.222 transações quase idênticas, sobrando 7 para os 112,5 milhões restantes. E elas apareceriam como anômalas em qualquer score, poluindo o ranking sem informar nada, já que são identificáveis por `WHERE is_coinbase`.

Elas permanecem em `silver.tx_enriched` e podem ser analisadas separadamente.

---

## O processo iterativo de ajuste

A matriz não saiu pronta. Foi construída, medida e corrigida em três rodadas, e esse processo é parte do resultado.

### Critério de diagnóstico

Duas métricas por feature:

| Métrica | Significado | Limite |
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

Correção: transformação logarítmica em `n_inputs`, `n_outputs`, `razao_in_out`, `taxa_relativa` e `dispersao_idade`.

Após a correção, `f_log_n_inputs` passou a ter desvio 0,50 sobre média 0,90, contra 15,75 sobre 2,59 antes.

### Rodada 2: feature sem variância

`f_razao_dust` apresentou média 0,0004 e desvio 0,012. Praticamente zero em todo o dataset, o que após padronização vira ruído sem poder discriminativo.

Correção: removida. O fenômeno permanece disponível em `silver.tx_enriched` para análise descritiva.

Na mesma rodada, `f_razao_valores_distintos` apresentou média 0,997 e desvio 0,039, ou seja, quase constante. Isso está correto (99,7% das transações têm todos os outputs com valores distintos), mas a feature contribuiria pouco.

Correção: invertida para `f_repeticao_valores`, onde 0 é normal, mais uma binária `f_padrao_mistura` que marca diretamente o padrão de interesse.

### Rodada 3: última cauda

`f_cv_outputs` apresentou 83,5 desvios até o máximo, com valor extremo de 51,7 (transação com outputs de magnitudes radicalmente distintas).

Correção: log aplicado, resultando em `f_log_cv_outputs` com 10,9 desvios até o máximo.

### Resultado final

As 21 features passaram no critério. Nenhuma domina o cálculo de distância e nenhuma é constante.

Três features aparecem com coeficiente de variação alto e ainda assim são aceitáveis: `f_padrao_mistura`, `f_repeticao_valores` e `f_razao_moeda_antiga`. O CV alto decorre da raridade do fenômeno, não de cauda pesada, e como são limitadas entre 0 e 1, não distorcem escala.

---

## Escolha do modelo

### Comparação

| Modelo | Amostra | Davies-Bouldin | Distância quadrática média |
|---|---|---:|---:|
| K=8 | 10% | **1,6050** | 11,5671 |
| K=5 | 1% | 1,7685 | 14,2682 |
| K=8 | 1% | 1,8024 | 12,4074 |
| K=8 | 100% | 1,8780 | 12,2222 |
| K=6 | 1% | 1,9580 | 14,0524 |
| K=12 | 1% | 1,9628 | 10,4067 |
| K=3 | 1% | 2,5100 | 17,8838 |

Menor Davies-Bouldin indica clusters mais compactos e separados. A distância quadrática média sempre cai com K maior, então não serve como critério isolado.

### K=8 apesar de K=5 ter métrica melhor

A diferença de Davies-Bouldin entre K=5 e K=8 é de 1,8%, desprezível. A distribuição dos clusters, porém, é bem diferente:

| Modelo | Maior cluster | Menor cluster |
|---|---:|---:|
| K=5 | 720.740 (64%) | 2.148 (0,2%) |
| K=8 | 396.409 (35%) | 2.082 (0,2%) |

Um cluster contendo 64% dos dados é um agrupamento genérico. Transações moderadamente incomuns caem dentro dele e não são flagradas. Em K=8, o comportamento normal está mais bem particionado, então o que fica de fora é mais provavelmente anômalo.

A justificativa é explícita: **a métrica de qualidade de clusterização não é o critério final quando o objetivo é isolar outliers**.

### Mais dados não melhoraram

A amostra de 10% (1,6050) superou tanto 1% (1,8024) quanto a base completa (1,8780).

Isso é contraintuitivo mas legítimo. O K-Means é sensível à inicialização e converge para ótimos locais. Com a base completa, o KMEANS++ sorteou centroides iniciais que levaram a uma configuração pior, e mais outliers participaram do cálculo dos centroides.

**Ressalva metodológica:** o `ML.EVALUATE` calcula as métricas sobre o próprio conjunto de treino de cada modelo, então a comparação entre amostras de tamanhos diferentes não é estritamente rigorosa. Uma comparação ideal avaliaria todos os modelos sobre um mesmo conjunto de validação separado.

---

## Detecção de anomalias

```sql
FROM ML.DETECT_ANOMALIES(
  MODEL `gold.kmeans_k8_10pct`,
  STRUCT(0.01 AS contamination),
  (SELECT * EXCEPT (_batch_id, _processed_at) FROM gold.tx_features WHERE ...)
)
```

### O que o `contamination` é e não é

Ele define a **fração do dataset declarada como anômala**. Com 0,01, o modelo ordena todas as transações por distância ao centroide mais próximo, pega o percentil 99, e marca tudo acima como anômalo.

Ele **não descobre nada**. É um corte imposto pelo analista. Com 0,05 marcaria 5%, com 0,20 marcaria 20%, e as mesmas transações continuariam nas mesmas posições do ranking.

O que o modelo realmente produz é o `normalized_distance`, que é contínuo. Por isso essa coluna é preservada na tabela: permite reavaliação com qualquer outro limiar sem retreinar nem reprocessar.

Com 112,5 milhões de transações, 1% resulta em aproximadamente 1,125 milhão de anomalias, o que é muito para investigação prática. A etapa 30 analisa a distribuição de distâncias buscando um corte natural nos dados, que seria justificativa empírica melhor que a convenção.

### O `EXCEPT` na subconsulta

`ML.DETECT_ANOMALIES` retorna todas as colunas da entrada. Como `tx_features` já tem `_batch_id` e `_processed_at`, e a criação da tabela adiciona os seus, os nomes colidiriam. Daí o `SELECT * EXCEPT (_batch_id, _processed_at)` na entrada.

---

## Estratégia de avaliação sem rótulos

Não existe gabarito de transações ilícitas neste dado. A avaliação combina três abordagens.

### Métricas internas de clusterização

Davies-Bouldin e distância quadrática média, comparados entre sete configurações. Mede qualidade da clusterização, não da detecção.

### Concordância com heurísticas estruturais

Esta é a mais informativa. Regras estruturais definidas por SQL determinístico, independentes do modelo, e verificação da taxa de sobreposição com as transações marcadas.

| Heurística | Selecionadas | Também marcadas | Concordância | Fator sobre o baseline |
|---|---:|---:|---:|---:|
| Alta contagem de outputs (>= 100) | 80.580 | 72.215 | 89,6% | 90x |
| Alta contagem de inputs (>= 100) | 313.954 | 124.842 | 39,8% | 40x |
| Moeda dormente (> 5 anos) | 27.505 | 2.863 | 10,4% | 10x |
| Alta repetição de valores | 43.619 | 1.641 | 3,8% | 4x |
| **Baseline: todas** | 112.500.276 | 1.119.290 | 1,0% | 1x |

O baseline torna o teste interpretável: um modelo aleatório produziria taxa próxima de 1% em todas as linhas.

**Duas ressalvas.** As regras são aproximações grosseiras, não definições rigorosas dos fenômenos que evocam. E há circularidade parcial nas duas primeiras linhas, porque as regras de contagem usam as mesmas grandezas que originam features do modelo. As duas linhas metodologicamente mais limpas são moeda dormente e alta repetição de valores.

Por isso a análise foi nomeada **concordância com heurísticas estruturais**, e não validação contra padrões conhecidos.

### Inspeção por cluster

O ranking global é dominado por uma única tipologia (consolidação massiva), o que satura os primeiros lugares. A inspeção correta usa `ROW_NUMBER() OVER (PARTITION BY centroid_id ...)` para extrair as mais distantes de cada cluster, revelando perfis distintos.

Tipologias observadas:

| Cluster | Distância | Perfil |
|---|---:|---|
| 2 | 5,10 a 5,26 | Consolidação massiva com dispersão. 700 a 950 inputs, 70 a 100 outputs, 52 a 68 valores distintos |
| 7 | 4,19 a 4,33 | Consolidação pura. 738 a 926 inputs, 7 a 13 outputs com 2 valores distintos, totais redondos |
| 4 | 3,08 a 3,10 | Moeda dormente. 1 input, 536 a 1.145 dias de idade |
| 6 | 1,90 a 1,92 | Valor zero com moeda envelhecida. 1 input, 2 outputs, 170 a 361 dias |
| 5 | 1,84 a 1,85 | Valor zero puro. 1 input, 1 output |
| 8 | 1,82 | Valor zero recente. 1 input, 2 outputs, idade zero |
| 3 | 1,70 | Alto valor com estrutura simples. 1 input, 2 a 3 outputs, 35 a 54 BTC |

O cluster 1 não produziu nenhuma anomalia, indicando que concentra o comportamento mais típico.

### Sobre balanceamento de classe

Não se aplica. Balanceamento é técnica de aprendizado supervisionado, onde classes raras ficam sub-representadas no treino.

Em clusterização não existe classe. O desequilíbrio é o próprio mecanismo de detecção: anomalias são raras por definição, então ficam longe dos centroides formados ao redor do comportamento comum. Sobreamostrar anomalias moveria os centroides na direção delas e **pioraria** a detecção.

### Sobre falsos positivos

Não existem falsos positivos no sentido estrito, porque não há rótulo. Uma consolidação de exchange não é erro do modelo: ela é genuinamente atípica. O que ela não é, é suspeita.

O problema não é de precisão, é de **priorização**. A entrega é um ranking, não uma classificação binária.

---

## Resultados da detecção

| Métrica | Valor |
|---|---:|
| Transações avaliadas | 112.500.276 |
| Marcadas como anomalia | 1.119.290 |
| Percentual | 0,995% |
| Clusters utilizados | 8 |
| Scores nulos | 0 |

### Distribuição das distâncias

| Percentil | Valor |
|---|---:|
| p50 | 0,847 |
| p90 | 1,187 |
| p95 | 1,347 |
| p99 | 1,685 |
| p99,9 | 2,241 |
| Máximo | 5,256 |

Apenas 9 transações no ano ultrapassam distância 5, nenhuma ultrapassa 10.

**A distribuição não apresenta quebra natural.** A transição do p99 ao máximo é suave, então o corte de 1% permanece uma convenção, não uma descoberta empírica.

### Análise de sensibilidade do corte

| Corte | Limiar | Transações | Perfil |
|---|---:|---:|---|
| 1% (p99) | 1,685 | 1.128.344 | Recall alto, inviável para revisão |
| 0,1% (p99,9) | 2,241 | 115.560 | Intermediário |
| Distância >= 3,0 | 3,000 | 12.472 | Filtra o incomum trivial |

O corte em 3,0 elimina os clusters dominados por transações de valor zero e preserva consolidação massiva e moeda dormente, resultando em conjunto de tamanho investigável.

### View de priorização

`gold.v_anomaly_priority` classifica em três faixas a partir do score contínuo, sem duplicar dado:

```sql
CASE
  WHEN normalized_distance >= 3.0   THEN 'alta'
  WHEN normalized_distance >= 2.241 THEN 'media'
  WHEN normalized_distance >= 1.685 THEN 'baixa'
  ELSE 'normal'
END
```

Os limiares 1,685 e 2,241 correspondem aos percentis 99 e 99,9 medidos.

## Validação contra padrões conhecidos

Esta é a mais convincente. Padrões estruturais são definidos por regra determinística em SQL, e verifica-se se o modelo os pontua alto sem ter sido ensinado sobre eles.

| Padrão | Regra | Ocorrências |
|---|---|---:|
| CoinJoin | `n_outputs >= 10 AND out_valores_distintos <= 2` | 43.619 |
| Moeda dormente | `idade_max_dias > 1825` | 27.505 |
| Fan-out | `n_outputs >= 100` | a medir |
| Fan-in | `n_inputs >= 100` | a medir |

A consulta inclui um **baseline** com todas as transações, que deve dar próximo de 1% (o `contamination`). Se os padrões conhecidos apresentarem taxa de detecção substancialmente acima do baseline, isso é evidência de detecção seletiva, não de acaso.

### Inspeção das top anomalias

As transações com maior `normalized_distance` são listadas com seus atributos originais, permitindo caracterização manual e verificação em exploradores de blockchain.

### Sobre balanceamento de classe

Não se aplica. Balanceamento é técnica de aprendizado supervisionado, onde classes raras ficam sub-representadas no treino.

Em clusterização não existe classe. O desequilíbrio é o próprio mecanismo de detecção: anomalias são raras por definição, então ficam longe dos centroides formados ao redor do comportamento comum. Sobreamostrar anomalias moveria os centroides na direção delas e **pioraria** a detecção.

O que existe de relacionado é uma limitação: o modelo treina em dados que já contêm as anomalias, que exercem alguma influência sobre a posição dos centroides. Mitigação possível seria remover extremos antes do treino, não implementada.

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

A numeração é global e intercala `gold/` e `model/`, porque a ordem de execução
não respeita a fronteira entre as duas pastas: o modelo é treinado sobre a matriz,
a inferência volta a escrever no `gold`, e a análise volta ao `model`.

| Script | Pasta | Descrição |
|---|---|---|
| `20-create-features-matrix.sql` | `gold/` | Matriz de features |
| `21-validate-features-matrix.sql` | `gold/` | Verificação de nulos |
| `22-analyze-features-variance.sql` | `gold/` | Diagnóstico de variância e cauda |
| `23-create-kmeans-k-sweep.sql` | `model/` | Modelos K = 3, 5, 6, 12 |
| `24-create-kmeans-k8-sample-sweep.sql` | `model/` | Modelos K = 8 em 1%, 10% e 100% |
| `25-evaluate-kmeans-models.sql` | `model/` | Comparação das sete configurações |
| `26-evaluate-training-info.sql` | `model/` | Convergência e tamanho dos clusters |
| `27-analyze-model-centroids.sql` | `model/` | Perfil de cada cluster |
| `28-create-anomaly-scores.sql` | `gold/` | Inferência sobre a base completa |
| `29-validate-anomaly-scores.sql` | `gold/` | Validação |
| `30-analyze-distance-cutoffs.sql` | `gold/` | Percentis e escolha do corte |
| `31-alignment-with-structural-heuristics.sql` | `model/` | Concordância com heurísticas estruturais |
| `32-analyze-top-anomalies.sql` | `gold/` | Ranking para inspeção manual |
| `33-create-anomaly-priority-view.sql` | `model/` | View de faixas de prioridade |
| `34-analyze-priority-view.sql` | `model/` | Distribuição das faixas |

Execute o passo 22 **antes** de treinar. Foi ele que revelou as caudas pesadas e a feature sem variância.

O passo 28 é o mais caro da camada, aplicando o modelo sobre 112,5 milhões de linhas.

---

## Status

Camada completa e validada. Modelo em produção: `gold.kmeans_k8_10pct`.

Artefatos finais: `gold.tx_features`, sete modelos K-Means, `gold.anomaly_scores` e `gold.v_anomaly_priority`.
