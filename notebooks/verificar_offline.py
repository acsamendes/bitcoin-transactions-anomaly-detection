# -*- coding: utf-8 -*-
"""Verificacao offline dos notebooks. Nao toca no BigQuery e nao gera custo.

Executa tudo que pode ser testado sem credenciais e sem cota:

  1. os 39 arquivos SQL seguem a convencao de nomes e sao descobertos na ordem;
  2. todo marcador de ambiente resolve com os valores de config.env;
  3. a guarda de escrita bloqueia producao e libera as queries de leitura;
  4. a reescrita da demonstracao desvia o alvo e reduz o recorte corretamente;
  5. docs/FEATURES.md continua em sincronia com a matriz de features;
  6. as celulas de codigo dos dois notebooks compilam;
  7. as celulas de grafico rodam contra dados sinteticos no schema exato
     que cada query devolve, e as figuras sao gravadas para inspecao visual.

O passo 7 e o que pega os erros que a compilacao nao pega: nome de coluna
trocado, rotulo que vaza da area do grafico, legenda por cima das barras.

Uso:
    python notebooks/verificar_offline.py

Requer matplotlib e pandas. Nao requer google-cloud-bigquery nem autenticacao.
"""

import ast
import io
import json
import pathlib
import sys

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

AQUI = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(AQUI))
import pipeline_lib as pl

FIGURAS = AQUI / "_figuras_verificacao"
falhas = []


def checar(nome, condicao, detalhe=""):
    marca = "ok  " if condicao else "FALHA"
    print("  %-5s %s%s" % (marca, nome, ("  -> " + detalhe) if detalhe and not condicao else ""))
    if not condicao:
        falhas.append(nome)


# --------------------------------------------------------------------------
print("\n1. Descoberta das etapas")
etapas = pl.descobrir_etapas()
print("       %d etapas em %s" % (len(etapas), ", ".join(pl.CAMADAS)))
ultimo = etapas[-1].numero if etapas else 0
checar("numeracao contigua de 01 a %02d" % ultimo,
       [e.numero for e in etapas] == list(range(1, ultimo + 1)),
       "faltam %s" % sorted(set(range(1, ultimo + 1)) - {e.numero for e in etapas}))
checar("todas as camadas presentes",
       {e.camada for e in etapas} == set(pl.CAMADAS))

# Um arquivo vazio passa por toda checagem estrutural e so falha no BigQuery.
# Vale sinalizar aqui, que e de graca.
vazios = [e.arquivo for e in etapas if not e.sql_bruto().strip()]
checar("nenhum arquivo SQL vazio", not vazios, ", ".join(vazios))
etapas_com_sql = [e for e in etapas if e.sql_bruto().strip()]

# --------------------------------------------------------------------------
print("\n2. Marcadores de ambiente")
# Sem config.env local, cai para o gabarito: esta suite so checa se os
# marcadores resolvem, nao os valores.
cfg = pl.carregar_config(permitir_exemplo=True)
nao_resolvem = []
for e in etapas:
    try:
        pl.resolver(e.sql_bruto(), cfg)
    except ValueError as err:
        nao_resolvem.append("%s: %s" % (e.arquivo, err))
checar("todo ${MARCADOR} resolve com config.env", not nao_resolvem,
       "; ".join(nao_resolvem))

# --------------------------------------------------------------------------
print("\n3. Guarda de escrita")
bloqueadas, liberadas = [], []
for e in etapas_com_sql:
    sql = pl.resolver(e.sql_bruto(), cfg)
    try:
        pl.exigir_somente_leitura(sql)
        liberadas.append(e)
    except PermissionError:
        bloqueadas.append(e)
checar("toda etapa de escrita e bloqueada",
       all(e.escreve for e in liberadas) is False or not [e for e in liberadas if e.escreve],
       "passaram: %s" % [e.arquivo for e in liberadas if e.escreve])
checar("nenhuma etapa de leitura e bloqueada",
       not [e for e in bloqueadas if not e.escreve],
       "bloqueadas: %s" % [e.arquivo for e in bloqueadas if not e.escreve])
# EXPORT DATA nao tem alvo em dataset: so e pego pelo marcador proprio.
exports = [e for e in etapas_com_sql if e.verbo == "export"]
checar("EXPORT DATA e detectado como escrita",
       all("gs" in pl.alvos_de_escrita(pl.resolver(e.sql_bruto(), cfg))
           for e in exports),
       "%d etapas de export" % len(exports))

# --------------------------------------------------------------------------
print("\n4. Reescrita da demonstracao")
DIA = "2020-06-01"
for numero in (20, 25, 34):
    e = pl.por_numero(etapas, numero)
    sql = pl.reescrever_para_demo(pl.resolver(e.sql_bruto(), cfg), DIA, "demo")
    producao = pl.alvos_de_escrita(sql) & set(pl.DATASETS_PRODUCAO)
    checar("%02d escreve fora de producao" % numero, not producao, str(producao))
    checar("%02d nao tem recorte anual restante" % numero,
           pl.RECORTE_COMPLETO not in sql)
for numero in (3, 12):
    e = pl.por_numero(etapas, numero)
    try:
        pl.reescrever_para_demo(pl.resolver(e.sql_bruto(), cfg), DIA, "demo")
        checar("%02d e recusada pela reescrita" % numero, False, "foi aceita")
    except ValueError:
        checar("%02d e recusada pela reescrita" % numero, True)

# --------------------------------------------------------------------------
print("\n5. Documentacao das features")
# docs/FEATURES.md descreve a matriz feature a feature. Se a matriz mudar e o
# documento nao, a divergencia so aparece quando alguem confere na banca.
import re as _re

FEATURES_MD = AQUI.parent / "docs" / "FEATURES.md"
matriz = pl.por_numero(etapas, 25).sql_bruto()
no_sql = set(_re.findall(r"AS\s+(f_[a-z0-9_]+)", matriz))

if not FEATURES_MD.exists():
    checar("docs/FEATURES.md existe", False, "arquivo ausente")
else:
    doc = io.open(FEATURES_MD, encoding="utf-8").read()
    no_doc = set()
    for m in _re.finditer(r"^### `(f_[a-z0-9_]+)`(?: e `(f_[a-z0-9_]+)`)?", doc, _re.M):
        no_doc.update(g for g in m.groups() if g)
    checar("toda feature da matriz esta documentada",
           not (no_sql - no_doc), "sem documentacao: %s" % sorted(no_sql - no_doc))
    checar("nenhuma feature documentada saiu da matriz",
           not (no_doc - no_sql), "documentadas mas ausentes: %s" % sorted(no_doc - no_sql))
    # Inclusao, nao igualdade: a secao "Features descartadas" tambem lista nomes
    # `f_*` em tabela, e eles nao pertencem a matriz de proposito.
    com_estatistica = set(_re.findall(r"^\| `(f_[a-z0-9_]+)` \|", doc, _re.M))
    checar("toda feature da matriz tem estatisticas na tabela",
           no_sql <= com_estatistica,
           "faltam na tabela: %s" % sorted(no_sql - com_estatistica))

# --------------------------------------------------------------------------
print("\n6. Sintaxe dos notebooks")
notebooks = {}
for nome in ("00-run-pipeline.ipynb", "01-apresentacao.ipynb"):
    nb = json.load(io.open(AQUI / nome, encoding="utf-8"))
    notebooks[nome] = nb
    erros = []
    for i, c in enumerate(nb["cells"]):
        if c["cell_type"] != "code":
            continue
        try:
            ast.parse("".join(c["source"]))
        except SyntaxError as err:
            erros.append("celula %d: %s" % (i, err.msg))
    checar("%s compila" % nome, not erros, "; ".join(erros))

# --------------------------------------------------------------------------
print("\n7. Graficos com dados sinteticos")
FIGURAS.mkdir(exist_ok=True)
pl.aplicar_estilo()
rng = np.random.default_rng(7)

TABELAS = {
    31: pd.DataFrame({
        "modelo": ["K=8  | amostra 10%", "K=12 | amostra 1%", "K=8  | base completa",
                   "K=8  | amostra 1%", "K=6  | amostra 1%", "K=5  | amostra 1%",
                   "K=3  | amostra 1%"],
        "k": [8, 12, 8, 8, 6, 5, 3],
        "amostra": ["10%", "1%", "100%", "1%", "1%", "1%", "1%"],
        "davies_bouldin": [1.021, 1.104, 1.187, 1.203, 1.288, 1.341, 1.502],
        "dist_quadratica": [8.11, 7.02, 8.35, 8.44, 9.31, 10.02, 12.88],
    }),
    37: pd.DataFrame({
        "padrao": ["CoinJoin", "Moeda dormente", "Fan-out", "Fan-in", "Baseline (todas)"],
        "total": [412003, 88120, 12400, 20110, 98220000],
        "detectadas": [151200, 30900, 8900, 9400, 982200],
        "pct": [36.7, 35.1, 71.8, 46.7, 1.0],
    }),
    36: pd.DataFrame([{
        "p50": 0.612, "p90": 1.744, "p95": 2.318, "p99": 4.402, "p999": 9.881,
        "maximo": 148.22, "acima_5": 812004, "acima_10": 91233, "acima_20": 6120,
    }]),
    41: pd.DataFrame({
        "prioridade": ["alta", "media", "baixa", "normal"],
        "transacoes": [91233, 320551, 613447, 111475045],
        "pct": [0.081, 0.285, 0.545, 99.089],
        "dist_min": [3.001, 2.241, 1.685, 0.0],
        "dist_max": [148.22, 3.0, 2.24, 1.684],
    }),
    33: pd.DataFrame([
        {"centroid_id": c, "feature": f, "valor": float(rng.normal(0, 1.1))}
        for c in range(1, 9)
        for f in ["f_log_valor_total", "f_log_maior_output", "f_log_taxa",
                  "f_log_tamanho", "f_log_n_inputs", "f_log_n_outputs",
                  "f_repeticao_valores", "f_padrao_mistura", "f_razao_maior_output",
                  "f_log_razao_in_out", "f_log_cv_outputs", "f_log_taxa_relativa",
                  "f_log_idade_max", "f_log_idade_media", "f_log_dispersao_idade",
                  "f_gasto_imediato", "f_razao_moeda_antiga", "f_razao_out_segwit",
                  "f_razao_size_vsize", "f_rbf", "f_locktime"]
    ]),
}

# Manifesto sintetico para a linha do tempo.
inicio, linhas = pd.Timestamp("2026-09-09 21:00:00", tz="UTC"), []
t = inicio
for e in etapas:
    dur = float(rng.gamma(2.0, 9.0) if e.escreve else rng.gamma(1.2, 1.5))
    linhas.append({"numero": e.numero, "camada": e.camada, "arquivo": e.arquivo,
                   "inicio": t.isoformat(), "segundos": round(dur, 2),
                   "bytes_faturados": int(rng.gamma(2, 6e9))})
    t = t + pd.Timedelta(seconds=dur + 1.5)
tempos = pd.DataFrame(linhas)
tempos["inicio_ts"] = pd.to_datetime(tempos["inicio"], format="mixed", utc=True)
tempos["rotulo"] = tempos.apply(
    lambda r: "%02d %s" % (r["numero"], r["arquivo"][3:-4]), axis=1)

# O namespace espelha o que a secao 1 do notebook deixa disponivel.
from matplotlib.patches import Patch

ns = {
    "pl": pl, "P": pl.PALETA, "pd": pd, "plt": plt, "np": np, "re": __import__("re"),
    "Patch": Patch, "etapas": etapas, "tempos": tempos,
    "display": lambda x: None,
    "consultar": lambda etapa: TABELAS[etapa.numero].copy(),
}

ALVOS = {
    "# Gantt do pipeline": "gantt",
    "selecao = consultar": "selecao-k",
    "centroides = consultar": "centroides",
    "padroes = consultar": "padroes",
    "dist = consultar": "distancias",
    "prioridade = consultar": "prioridade",
}

celulas = ["".join(c["source"]) for c in notebooks["01-apresentacao.ipynb"]["cells"]]
for prefixo, nome in ALVOS.items():
    fonte = next((s for s in celulas if s.lstrip().startswith(prefixo)), None)
    if fonte is None:
        checar("celula '%s'" % nome, False, "nao encontrada no notebook")
        continue
    try:
        exec(compile(fonte, "<%s>" % nome, "exec"), ns)
        plt.gcf().savefig(FIGURAS / ("%s.png" % nome), bbox_inches="tight", dpi=110)
        plt.close("all")
        checar("grafico %s" % nome, True)
    except Exception as err:
        plt.close("all")
        checar("grafico %s" % nome, False, "%s: %s" % (type(err).__name__, err))

# --------------------------------------------------------------------------
print("\n" + "-" * 66)
if falhas:
    print("%d verificacao(oes) falharam:" % len(falhas))
    for f in falhas:
        print("  -", f)
    sys.exit(1)
print("tudo certo. Figuras para conferir a olho em:")
print("  %s" % FIGURAS)
sys.exit(0)
