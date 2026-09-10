# Features do Modelo

As 21 features de `gold.tx_features`, seu cálculo e a justificativa de cada uma.

---

## Sumário

- [Visão geral](#visão-geral)
- [Escala](#escala)
- [Estrutura](#estrutura)
- [Contexto de rede](#contexto-de-rede)
- [Dormência](#dormência)
- [Composição](#composição)
- [Comportamento](#comportamento)
- [Estatísticas descritivas](#estatísticas-descritivas)
- [Features descartadas](#features-descartadas)
- [Como as features mapeiam para padrões conhecidos](#como-as-features-mapeiam-para-padrões-conhecidos)

---

## Visão geral

Cada linha da matriz é **uma transação**, e cada feature é calculada apenas com os dados daquela transação. A única exceção é `f_log_taxa_relativa`, cujo denominador vem da agregação horária da rede.

Transações coinbase estão excluídas, por não possuírem inputs nem taxa comparável.

| Família | Features | O que capturam |
|---|---:|---|
| Escala | 4 | Magnitude da transação |
| Estrutura | 7 | Geometria de inputs e outputs |
| Contexto de rede | 1 | Desvio em relação às condições do momento |
| Dormência | 5 | Idade das moedas consumidas |
| Composição | 2 | Tipos de script utilizados |
| Comportamento | 2 | Escolhas de construção da transação |

**Total: 21.**

### Por que 21 e não 45

A camada Silver disponibiliza mais de 40 colunas agregadas. Levar todas seria contraproducente por dois motivos.

O primeiro é a maldição da dimensionalidade: em espaço de alta dimensão, as distâncias entre pontos convergem e tudo tende a ficar equidistante, o que destrói exatamente o mecanismo que o K-Means usa para decidir.

O segundo é interpretabilidade. Com 21 dimensões já é trabalhoso caracterizar cada cluster em uma frase; com 45 seria inviável.

---

## Escala

Todas com transformação logarítmica, obrigatória dada a cauda pesada. Os valores de output variam de 0 a 4,38 trilhões de satoshis; sem log, o K-Means mediria essencialmente "qual é a transação mais cara" e ignoraria as outras dimensões.

O `+1` antes do log evita indefinição em zero.

### `f_log_valor_total`

```sql
LOG(t.out_total + 1)
```

Soma de todos os outputs, em satoshis.

### `f_log_maior_output`

```sql
LOG(t.out_max + 1)
```

O maior output isolado. Distingue uma transação que move muito num pagamento único de outra que move o mesmo total pulverizado.

### `f_log_taxa`

```sql
LOG(t.fee + 1)
```

Taxa absoluta paga ao minerador. Complementa a taxa relativa: uma transação pode pagar muito em termos absolutos e ainda assim estar na média da hora.

### `f_log_tamanho`

```sql
LOG(t.virtual_size + 1)
```

Peso da transação em vbytes. Proxy de complexidade estrutural, já que mais inputs e outputs significam mais bytes.

---

## Estrutura

### `f_log_n_inputs` e `f_log_n_outputs`

```sql
LOG(t.n_inputs + 1)
LOG(t.n_outputs + 1)
```

Contagens de inputs e outputs.

O log não estava na versão inicial. A análise de variância mostrou que `f_n_inputs` tinha 93 desvios padrão entre a média e o valor máximo (1.471 inputs contra mediana de 2), o que faria uma única transação dominar o cálculo de distância após a padronização. Após o log, caiu para 12,7 desvios.

### `f_repeticao_valores`

```sql
IFNULL(1 - SAFE_DIVIDE(t.out_valores_distintos, t.n_outputs), 0)
```

Fração de outputs com valor repetido. Zero significa que todos os outputs têm valores diferentes, o comportamento normal em 99,7% dos casos.

Esta é a feature mais diretamente ligada à detecção de mistura. Um CoinJoin tem dezenas de outputs com valor idêntico para quebrar a heurística de propriedade comum, então o valor sobe.

A versão original era a razão direta (`out_valores_distintos / n_outputs`), com média 0,997. Foi invertida para que zero represente o caso normal, tornando a interpretação mais natural.

### `f_padrao_mistura`

```sql
IF(t.n_outputs >= 5
   AND IFNULL(SAFE_DIVIDE(t.out_valores_distintos, t.n_outputs), 1) <= 0.5, 1, 0)
```

Binária que marca diretamente o padrão de mistura: pelo menos 5 outputs, com no máximo metade dos valores distintos.

Prevalência de 0,19% (aproximadamente 210 mil transações).

Como binária rara, contribui pouco para os centroides, mas permanece na matriz como marcador interpretável e é útil na análise de validação.

### `f_razao_maior_output`

```sql
IFNULL(SAFE_DIVIDE(t.out_max, NULLIF(t.out_total, 0)), 1)
```

Que fração do valor total está no maior output.

Um pagamento comum tem dois outputs desbalanceados (o pagamento e o troco), então a razão fica alta. Média observada de 0,872. Uma distribuição em lote tem outputs equilibrados e a razão cai. Separa "pagar alguém" de "distribuir para muitos".

### `f_log_razao_in_out`

```sql
LOG(IFNULL(SAFE_DIVIDE(t.n_inputs, t.n_outputs), 0) + 1)
```

Razão entre número de inputs e outputs, indicando a direção do fluxo.

Razão alta significa consolidação (juntar muitas moedas em poucas), típico de exchange varrendo carteiras. Razão baixa significa dispersão.

### `f_log_cv_outputs`

```sql
LOG(IFNULL(SAFE_DIVIDE(t.out_desvio, NULLIF(t.out_media, 0)), 0) + 1)
```

Coeficiente de variação dos valores dos outputs, medindo dispersão de forma independente de escala.

Valor perto de zero significa outputs uniformes, o que reforça o sinal de CoinJoin e de pagamento em lote.

O log foi adicionado na terceira rodada de ajustes: a versão sem log tinha 83,5 desvios até o máximo (uma transação com CV de 51,7, misturando um output enorme com vários dust). Após o log, 10,9 desvios.

O desvio padrão usa `STDDEV_POP` em vez de `STDDEV`, porque o amostral retorna nulo para transações de output único, que são comuns.

---

## Contexto de rede

### `f_log_taxa_relativa`

```sql
LOG(IFNULL(SAFE_DIVIDE(t.fee_por_vbyte, NULLIF(n.fee_vbyte_mediana, 0)), 1) + 1)
```

Taxa por vbyte dividida pela mediana daquela hora, em log.

Esta é a feature que justifica a existência de `silver.network_context_hourly`.

Uma taxa de 50 sat/vB não significa nada isolada. Se a mediana da hora era 8, é urgência anômala. Se era 45, é comportamento normal em período de congestionamento.

Sem essa normalização, o modelo marcaria todo o dia 12 de março de 2020 como anômalo, porque a mediana de taxa explodiu no crash da COVID. Isso é evento de rede, não comportamento suspeito, e seria ruído no resultado.

O log foi necessário porque a razão bruta chegava a 53 mil vezes a mediana no caso extremo.

---

## Dormência

Cinco features derivadas de `silver.coin_age`. Movimento súbito de moeda antiga é padrão clássico de fundos roubados, carteira comprometida ou baleia se movendo.

### `f_log_idade_max`

```sql
LOG(IFNULL(t.idade_max_dias, 0) + 1)
```

Idade da moeda mais antiga consumida, em dias.

A feature clássica de dormência. O valor máximo observado no dataset é 3.268 dias, quase nove anos: moeda de 2011 sendo gasta em 2020.

### `f_log_idade_media`

```sql
LOG(IFNULL(t.idade_media_dias, 0) + 1)
```

Idade típica das moedas gastas. Distingue uma transação que junta uma moeda antiga com várias recentes de outra em que todas são antigas.

### `f_log_dispersao_idade`

```sql
LOG(IFNULL(SAFE_DIVIDE(t.idade_max_dias, NULLIF(t.idade_media_dias, 0)), 1) + 1)
```

Razão entre a idade máxima e a média.

Valor alto significa que a transação mistura moedas de épocas muito distintas, padrão de consolidação de carteira acumulada ao longo de anos. Valor perto de 1 significa moedas da mesma safra.

### `f_gasto_imediato`

```sql
IF(IFNULL(t.idade_min_horas, 999) < 1, 1, 0)
```

Marca transações que gastam alguma moeda criada há menos de uma hora.

Foi definida como binária, e não como a variável contínua `idade_min_horas`, porque 53,6 milhões de transações (quase metade do dataset) têm idade mínima igual a zero. Como contínua, a feature teria variância concentrada e pouca utilidade. Como flag, captura o comportamento de gasto instantâneo, típico de serviços automatizados e exchanges.

Média observada de 0,477, ou seja, distribuição perto de 50/50, o que é ideal para uma binária.

### `f_razao_moeda_antiga`

```sql
IFNULL(SAFE_DIVIDE(t.moedas_acima_1ano, t.n_inputs), 0)
```

Fração dos inputs que veio de moeda com mais de um ano. Complementa as anteriores medindo a proporção, não o extremo.

---

## Composição

### `f_razao_out_segwit`

```sql
IFNULL(SAFE_DIVIDE(t.out_segwit, t.n_outputs), 0)
```

Proporção de outputs em SegWit, contando `witness_v0_keyhash` e `witness_v0_scripthash`.

Em 2020 a adoção de SegWit estava em transição, presente em 22% das transações. A feature separa populações de carteiras: software moderno contra legado.

**Exemplo de cálculo.** Uma transação com 4 outputs, sendo 2 em SegWit: `2 / 4 = 0,5`. Metade dos outputs vai para endereços SegWit.

### `f_razao_size_vsize`

```sql
IFNULL(SAFE_DIVIDE(t.size, NULLIF(t.virtual_size, 0)), 1)
```

Razão entre tamanho bruto e tamanho virtual.

SegWit desconta o peso dos dados de testemunha no cálculo do tamanho virtual, então essa razão indica quanto da transação está em witness. É um proxy estrutural do tipo de gasto, complementar à feature anterior.

Faixa observada: 1,0 a 3,69.

---

## Comportamento

### `f_rbf`

```sql
IF(t.rbf_signaled, 1, 0)
```

Sinalização de Replace-By-Fee, conforme o BIP125.

RBF permite substituir uma transação parada na mempool por outra pagando taxa maior. A sinalização é feita por input, com `sequence < 0xFFFFFFFE`, e a regra é por transação: basta um input sinalizar. Por isso a agregação na Silver usa `LOGICAL_OR`, não média.

A escolha de habilitar RBF é uma pista sobre o tipo de ator. Carteiras de usuário comum frequentemente habilitam por padrão; exchanges e serviços grandes muitas vezes desabilitam, porque calculam a taxa corretamente e não querem a complexidade.

Prevalência de 11,6%.

**Ressalva:** a semântica de `sequence` tem interações com o BIP68 (timelocks relativos), então a detecção deve ser descrita como sinalização aproximada de RBF, não como detecção exata.

### `f_locktime`

```sql
IF(t.lock_time > 0, 1, 0)
```

Transação com trava temporal explícita, impedindo mineração antes de um bloco ou horário específico.

É relativamente raro (21% das transações) e indica construção deliberada, não uso casual de carteira.

---

## Estatísticas descritivas

Valores medidos sobre as 112.500.276 linhas da matriz final.

| Feature | Média | Desvio | Mínimo | Máximo | CV | Desvios até o máx. |
|---|---:|---:|---:|---:|---:|---:|
| `f_log_valor_total` | 15,479 | 2,721 | 0,000 | 30,535 | 0,18 | 5,5 |
| `f_log_maior_output` | 15,315 | 2,722 | 0,000 | 30,502 | 0,18 | 5,6 |
| `f_log_taxa` | 8,905 | 1,543 | 0,000 | 19,671 | 0,17 | 7,0 |
| `f_log_tamanho` | 5,559 | 0,637 | 4,443 | 12,352 | 0,11 | 10,7 |
| `f_log_n_inputs` | 0,901 | 0,503 | 0,693 | 7,294 | 0,56 | 12,7 |
| `f_log_n_outputs` | 1,114 | 0,413 | 0,693 | 8,852 | 0,37 | 18,7 |
| `f_repeticao_valores` | 0,003 | 0,039 | 0,000 | 0,999 | 13,31 | 25,3 |
| `f_padrao_mistura` | 0,002 | 0,043 | 0,000 | 1,000 | 23,11 | 23,1 |
| `f_razao_maior_output` | 0,872 | 0,169 | 0,001 | 1,000 | 0,19 | 0,8 |
| `f_log_razao_in_out` | 0,599 | 0,473 | 0,000 | 7,294 | 0,79 | 14,1 |
| `f_log_cv_outputs` | 0,465 | 0,320 | 0,000 | 3,964 | 0,69 | 10,9 |
| `f_log_taxa_relativa` | 0,745 | 0,505 | 0,000 | 11,123 | 0,68 | 20,5 |
| `f_log_idade_max` | 0,650 | 1,335 | 0,000 | 8,323 | 2,05 | 5,7 |
| `f_log_idade_media` | 0,581 | 1,238 | 0,000 | 8,323 | 2,13 | 6,3 |
| `f_log_dispersao_idade` | 0,751 | 0,198 | 0,693 | 6,865 | 0,26 | 30,9 |
| `f_gasto_imediato` | 0,477 | 0,500 | 0,000 | 1,000 | 1,05 | 1,0 |
| `f_razao_moeda_antiga` | 0,009 | 0,088 | 0,000 | 1,000 | 10,27 | 11,3 |
| `f_razao_out_segwit` | 0,115 | 0,238 | 0,000 | 1,000 | 2,08 | 3,7 |
| `f_razao_size_vsize` | 1,292 | 0,332 | 1,000 | 3,688 | 0,26 | 7,2 |
| `f_rbf` | 0,116 | 0,320 | 0,000 | 1,000 | 2,77 | 2,8 |
| `f_locktime` | 0,210 | 0,408 | 0,000 | 1,000 | 1,94 | 1,9 |

Nenhuma feature excede 50 desvios até o máximo, o critério adotado para cauda pesada. Nenhuma tem desvio abaixo de 0,01, o critério para variância insuficiente.

Três features apresentam coeficiente de variação acima de 4 (`f_repeticao_valores`, `f_padrao_mistura` e `f_razao_moeda_antiga`). Isso decorre da raridade do fenômeno que descrevem, não de cauda pesada. Como são limitadas ao intervalo de 0 a 1, não distorcem a escala após padronização.

### Nota sobre correlação

`f_log_valor_total` e `f_log_maior_output` têm médias e desvios quase idênticos (15,479 e 15,315, ambos com desvio 2,72), indicando correlação alta. Isso é esperado, já que o maior output representa em média 87% do total.

Features redundantes não quebram o K-Means, mas dão peso duplo à mesma dimensão. `f_log_maior_output` seria a candidata natural a remoção em uma iteração futura, já que `f_razao_maior_output` já carrega a informação de proporção.

---

## Features descartadas

| Feature | Motivo |
|---|---|
| `out_opreturn` | Sempre zero. A categoria `nulldata` não é populada por este parser; OP_RETURN aparece como `nonstandard` com valor zero |
| `f_razao_dust` | Variância desprezível (média 0,0004, desvio 0,012). Após padronização, viraria ruído |
| `out_multisig_script` | Densidade insuficiente (4.464 casos em 112 milhões) |
| Mínimos e médias de valor | Correlacionados com os máximos correspondentes |
| Contagens absolutas de dust e SegWit | Substituídas pelas razões, mais informativas |
| `in_enderecos_unicos_distintos` | A heurística de propriedade comum já está implícita em `n_inputs` |
| `out_valor_zero` e `out_nonstandard` | Altamente correlacionados entre si (os zerados são todos `nonstandard`). Nenhum dos dois foi incluído; se um fosse, `out_nonstandard` como razão seria o mais informativo |

O caso do `out_opreturn` merece destaque metodológico: a feature teria entrado no modelo como coluna constante se a análise de densidade não tivesse sido executada antes do treino.

---

## Como as features mapeiam para padrões conhecidos

| Padrão | Assinatura esperada nas features |
|---|---|
| **CoinJoin** | `f_repeticao_valores` alto, `f_padrao_mistura` igual a 1, `f_log_cv_outputs` baixo, `f_log_n_outputs` alto |
| **Peeling chain** | `f_razao_maior_output` muito alto (acima de 0,9), `f_log_n_outputs` baixo, encadeamento sequencial |
| **Fan-out / distribuição** | `f_log_n_outputs` muito alto, `f_log_razao_in_out` baixo, `f_log_cv_outputs` baixo |
| **Fan-in / consolidação** | `f_log_n_inputs` muito alto, `f_log_razao_in_out` alto |
| **Moeda dormente** | `f_log_idade_max` alto, `f_razao_moeda_antiga` alto, `f_gasto_imediato` igual a 0 |
| **Consolidação de carteira antiga** | `f_log_dispersao_idade` alto, `f_log_n_inputs` alto |
| **Urgência anômala** | `f_log_taxa_relativa` alto com `f_log_tamanho` normal |
| **Automação / serviço** | `f_gasto_imediato` igual a 1, `f_rbf` consistente, valores regulares |

Nenhuma dessas combinações foi ensinada ao modelo. A etapa 31 do pipeline verifica se o K-Means as identifica espontaneamente, comparando a taxa de detecção de cada padrão contra o baseline de 1% definido pelo `contamination`.
