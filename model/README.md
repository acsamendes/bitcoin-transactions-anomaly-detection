# Camada Model

Treino, comparação e avaliação dos modelos de clusterização. Consome `gold.tx_features` e produz os artefatos de machine learning usados pela camada Gold para gerar os scores.

---

## Sumário

- [Por que uma camada separada](#por-que-uma-camada-separada)
- [Onde os modelos residem](#onde-os-modelos-residem)
- [Escolha do algoritmo](#escolha-do-algoritmo)
- [Estratégia de amostragem](#estratégia-de-amostragem)
- [Modelos treinados](#modelos-treinados)
- [Seleção do modelo](#seleção-do-modelo)
- [Convergência](#convergência)
- [Tipologias identificadas](#tipologias-identificadas)
- [Avaliação sem rótulos](#avaliação-sem-rótulos)
- [Limitações](#limitações)
- [Ordem de execução](#ordem-de-execução)

---

## Por que uma camada separada

A fronteira entre dado e modelo é real e vale ser explícita.

`gold.tx_features` é uma tabela como qualquer outra: serve ao modelo, mas também a análise exploratória ou a BI. Ela existe independente de qualquer decisão de modelagem.

Modelos não são dados, são artefatos de outro tipo. E o que acontece aqui (comparar sete configurações, medir índices de qualidade, testar volumes de amostra) é ciclo de experimentação, não transformação de dados. Reprocessar a Gold e retreinar o modelo são operações com cadências diferentes.

A tabela de scores fica na Gold, e não aqui, por um critério simples: **tudo que se consulta está na Gold, tudo que se treina está na Model**.

---

## Escolha do algoritmo

O BigQuery ML oferece quatro famílias não supervisionadas. A avaliação de cada uma:

| Modelo | Adequação | Motivo |
|---|---|---|
| **KMEANS** | Escolhido | Clusterização, que é uma das três categorias exigidas pelo enunciado. É o mais interpretável: `ML.CENTROIDS` permite caracterizar cada grupo em uma frase |
| PCA | Descartado | Redução de dimensionalidade, categoria que o enunciado não lista. Serve como análise complementar, não como modelo principal |
| AUTOENCODER | Descartado | Captura padrões não lineares que os demais perdem, mas é caixa preta. |
| MATRIX_FACTORIZATION | Não aplicável | Destinado a sistemas de recomendação |
| ARIMA_PLUS | Não aplicável | Séries temporais. Serviria para detectar períodos anômalos na rede, que é outra pergunta |

Sobre modelos supervisionados como `BOOSTED_TREE_CLASSIFIER` (XGBoost): exigiriam uma coluna de rótulo indicando o que é anômalo, que não existe. Rotular por heurística e treinar o classificador para reproduzir a própria heurística seria circular, e não descobriria nada novo.

### Configuração adotada

```sql
OPTIONS (
  model_type = 'KMEANS',
  num_clusters = K,
  standardize_features = TRUE,
  kmeans_init_method = 'KMEANS++',
  max_iterations = 30
)
```

`standardize_features = TRUE` aplica z-score em cada feature. Sem isso, `f_log_valor_total` (média 15,5) dominaria as binárias (média entre 0 e 1). Note que isso normaliza a **escala das features**, não a proporção de anomalias, que é assunto diferente.

`KMEANS++` escolhe os centroides iniciais de forma informada em vez de aleatória, melhorando a convergência.

`max_iterations = 30` é folgado de propósito. Os modelos convergiram em 5 a 6 iterações.

---

## Estratégia de amostragem

O treino usa amostra selecionada por hash, não por sorteio:

```sql
AND MOD(ABS(FARM_FINGERPRINT(transaction_hash)), 100) = 0
```

`FARM_FINGERPRINT` gera um inteiro determinístico a partir do hash. O `MOD(..., 100) = 0` seleciona aproximadamente 1 em cada 100, e como o hash de uma transação Bitcoin é essencialmente aleatório, a distribuição dos restos é uniforme.

Duas vantagens sobre `RAND() < 0.01`:

**Comparabilidade.** Os modelos comparados veem exatamente as mesmas linhas, então a diferença nas métricas vem do K e não da amostra.

**Reprodutibilidade.** Reexecutar o script produz o mesmo modelo.

Para 10%, o divisor vira 10. Como a lógica é a mesma, a amostra de 10% **contém** a de 1%, o que torna a comparação entre volumes ainda mais limpa.

Uma observação sobre custo: `MOD(FARM_FINGERPRINT(...))` não reduz os bytes lidos, porque o BigQuery lê todas as linhas para depois filtrar. O que ela economiza é tempo de treino. Para reduzir a leitura seria necessário `TABLESAMPLE SYSTEM`, que amostra blocos de armazenamento inteiros.

---

## Modelos treinados

| Modelo | K | Amostra | Linhas de treino aproximadas |
|---|---:|---|---:|
| `kmeans_k3` | 3 | 1% | 1.125.000 |
| `kmeans_k5` | 5 | 1% | 1.125.000 |
| `kmeans_k6` | 6 | 1% | 1.125.000 |
| `kmeans_k8_1pct` | 8 | 1% | 1.125.000 |
| `kmeans_k12` | 12 | 1% | 1.125.000 |
| **`kmeans_k8_10pct`** | **8** | **10%** | **11.250.000** |
| `kmeans_k8_full` | 8 | 100% | 112.500.276 |

O modelo em produção é `kmeans_k8_10pct`.

### Como os valores de K foram escolhidos

**Pelo domínio.** Os comportamentos plausíveis em transações Bitcoin (pagamento com troco, consolidação, distribuição em lote, mistura, moeda dormente, dados sem valor, gasto automatizado) sugerem algo entre 5 e 10 grupos naturais.

Os valores 3, 5, 6, 8 e 12 cobrem essa faixa com espaçamento suficiente para que as métricas difiram de forma visível.

---

## Seleção do modelo

| Modelo | Amostra | Davies-Bouldin | Distância quadrática média |
|---|---|---:|---:|
| **K=8** | **10%** | **1,6050** | **11,5671** |
| K=5 | 1% | 1,7685 | 14,2682 |
| K=8 | 1% | 1,8024 | 12,4074 |
| K=8 | 100% | 1,8780 | 12,2222 |
| K=6 | 1% | 1,9580 | 14,0524 |
| K=12 | 1% | 1,9628 | 10,4067 |
| K=3 | 1% | 2,5100 | 17,8838 |

Menor Davies-Bouldin indica clusters mais compactos e separados. A distância quadrática média sempre cai com K maior, então não decide sozinha.

### K=8 apesar de K=5 ter métrica ligeiramente melhor

A diferença entre K=5 e K=8 na amostra de 1% é de 1,8%, desprezível. A distribuição dos clusters, porém, é bem diferente:

| Modelo | Maior cluster | Menor cluster |
|---|---:|---:|
| K=5 | 720.740 (64%) | 2.148 (0,2%) |
| K=8 | 396.409 (35%) | 2.082 (0,2%) |

Um cluster contendo 64% dos dados é um agrupamento genérico: transações moderadamente incomuns caem dentro dele e não são isoladas.

A justificativa é explícita: **a métrica de qualidade de clusterização não é o critério final quando o objetivo é isolar outliers.** Mais clusters modelam melhor a diversidade do comportamento normal, deixando as anomalias mais afastadas.

### Mais dados não melhoraram monotonicamente

A amostra de 10% (1,6050) superou tanto 1% (1,8024) quanto a base completa (1,8780).

Isso é contraintuitivo mas legítimo. O K-Means é sensível à inicialização e converge para ótimos locais. Com a base completa, o KMEANS++ sorteou centroides iniciais que levaram a uma configuração pior, e mais outliers participaram do cálculo dos centroides.

**Ressalva metodológica:** o `ML.EVALUATE` calcula as métricas sobre o próprio conjunto de treino de cada modelo, então a comparação entre amostras de tamanhos diferentes não é estritamente rigorosa. Uma comparação ideal avaliaria todos os modelos sobre um mesmo conjunto de validação separado.

---

## Convergência

`ML.TRAINING_INFO` mostra uma linha por iteração, com a perda e o tamanho de cada cluster.

Ambos os modelos K=8 convergiram bem antes do teto de 30 iterações: K=8 em 1% parou na iteração 5, e K=5 na iteração 4. A perda estabilizou com variação inferior a 1% na última iteração (12,49 para 12,41 no caso do K=8).

Isso confirma que `max_iterations = 30` estava folgado e o treino não foi truncado.

A consulta também expõe a evolução do tamanho dos clusters ao longo das iterações, útil para diagnosticar configurações instáveis.

---

## Tipologias identificadas

`ML.CENTROIDS` retorna o perfil de cada cluster nas 21 dimensões. Combinado com a inspeção das transações mais distantes de cada cluster, revela perfis reconhecíveis.

| Cluster | Distância máxima | Perfil | Features dominantes |
|---|---:|---|---|
| 2 | 5,26 | Consolidação massiva com dispersão. 700 a 950 inputs, 70 a 100 outputs, 52 a 68 valores distintos | `f_log_n_inputs` e `f_log_n_outputs` altos |
| 7 | 4,33 | Consolidação pura. 738 a 926 inputs, 7 a 13 outputs com 2 valores distintos, totais redondos | `f_log_n_inputs` alto, `f_repeticao_valores` alto |
| 4 | 3,10 | Moeda dormente. 1 input, 536 a 1.145 dias de idade | `f_log_idade_max` alto |
| 6 | 1,92 | Valor zero com moeda envelhecida. 1 input, 2 outputs, 170 a 361 dias | `f_log_valor_total` mínimo |
| 5 | 1,85 | Valor zero puro. 1 input, 1 output | `f_log_n_outputs` mínimo |
| 8 | 1,82 | Valor zero recente. 1 input, 2 outputs, idade zero | `f_gasto_imediato` igual a 1 |
| 3 | 1,70 | Alto valor com estrutura simples. 1 input, 2 a 3 outputs, 35 a 54 BTC | `f_log_valor_total` alto |

O cluster 1 não produziu nenhuma transação marcada como anomalia, indicando que concentra o comportamento mais típico.

### Nota sobre a inspeção por cluster

O ranking global é saturado por uma única tipologia: as vinte transações mais distantes são todas consolidações massivas do cluster 2. Isso indica que a contagem de inputs domina a distância apesar da transformação logarítmica.

A inspeção correta usa `ROW_NUMBER() OVER (PARTITION BY centroid_id ORDER BY normalized_distance DESC)` para extrair as mais distantes de cada cluster separadamente, revelando os perfis distintos acima.

---

## Avaliação sem rótulos

Não existe gabarito de transações ilícitas neste dado. A avaliação combina três abordagens.

### 1. Métricas internas de clusterização

Davies-Bouldin e distância quadrática média, comparados entre sete configurações. Medem qualidade da clusterização, não da detecção.

### 2. Concordância com heurísticas estruturais

Regras estruturais definidas por SQL determinístico, independentes do modelo, com verificação da taxa de sobreposição com as transações marcadas.

| Heurística | Selecionadas | Também marcadas | Concordância | Fator sobre o baseline |
|---|---:|---:|---:|---:|
| Alta contagem de outputs (>= 100) | 80.580 | 72.215 | 89,6% | 90x |
| Alta contagem de inputs (>= 100) | 313.954 | 124.842 | 39,8% | 40x |
| Moeda dormente (> 5 anos) | 27.505 | 2.863 | 10,4% | 10x |
| Alta repetição de valores | 43.619 | 1.641 | 3,8% | 4x |
| **Baseline: todas as transações** | 112.500.276 | 1.119.290 | 1,0% | 1x |

O baseline torna o teste interpretável: um modelo aleatório produziria taxa próxima de 1% em todas as linhas.

**Duas ressalvas.**

As regras são aproximações grosseiras, não definições rigorosas. "Alta contagem de outputs" é compatível com dispersão de fundos, mas também ocorre em pagamento em lote legítimo de exchange. Por isso a análise foi nomeada **concordância com heurísticas estruturais**, e não validação contra padrões conhecidos.

### 3. Inspeção qualitativa

As transações mais distantes de cada cluster são caracterizadas manualmente.

### Sobre balanceamento de classe

Não se aplica. Balanceamento é técnica de aprendizado supervisionado, onde classes raras ficam sub-representadas no treino.

Em clusterização não existe classe. O desequilíbrio é o próprio mecanismo de detecção: anomalias são raras por definição, então ficam longe dos centroides formados ao redor do comportamento comum. Sobreamostrar anomalias moveria os centroides na direção delas e **pioraria** a detecção.

---

## Limitações

**Ausência de rótulos.** O modelo detecta desvio de comportamento, não crime. A maior parte do detectado é atividade legítima e apenas incomum.

**Treino sobre dados contaminados.** O K-Means aprende os centroides a partir de dados que já contêm as anomalias, que exercem alguma influência sobre a posição dos centroides.

**Baixa sensibilidade a padrões raros.** `f_repeticao_valores` e `f_padrao_mistura` têm desvio padrão de 0,039 e 0,043. Após a padronização, contribuem pouco para a distância euclidiana comparadas às features de contagem. Este é o custo de usar K-Means para capturar exceções: o algoritmo encontra estrutura na massa dos dados, não nas raridades.

**Ranking dominado por uma dimensão.** As transações globalmente mais distantes são todas do mesmo perfil, contornado pela análise por cluster.

**Duas features correlacionadas.** `f_log_valor_total` e `f_log_maior_output` têm médias e desvios quase idênticos, dando peso duplo à mesma dimensão. Candidata a remoção em iteração futura.

---

## Ordem de execução

| Nº | Consulta | Descrição |
|---:|---|---|
| 23 | Criação - Modelos K-Means Alternativos | K = 3, 5, 6 e 12, todos em amostra de 1% |
| 24 | Criação - Modelos 8-Means | K = 8 em 1%, 10% e 100% |
| 25 | Avaliação - Comparação de Modelos K-Means | `ML.EVALUATE` das sete configurações |
| 26 | Avaliação - Informações de Treinamento | `ML.TRAINING_INFO`: convergência e tamanho dos clusters |
| 27 | Análise - Centroides do Modelo | `ML.CENTROIDS` do modelo escolhido |
| 31 | Avaliação - Concordância com Heurísticas Estruturais | Sobreposição com regras independentes |

As consultas 23 a 27 precedem a geração dos scores na camada Gold (consulta 28). A consulta 31 vem depois, porque depende dos scores prontos.

O modelo `kmeans_k8_full` é o mais demorado dos sete e apresentou a pior métrica entre as três configurações de K=8. Ele existe como evidência de que o aumento do volume de treino não melhorou o resultado, não como candidato a produção.
