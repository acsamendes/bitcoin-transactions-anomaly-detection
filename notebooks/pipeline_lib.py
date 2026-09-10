"""Runtime compartilhado pelos dois notebooks do repositorio.

00-run-pipeline.ipynb  executa o pipeline inteiro e grava o manifesto.
01-apresentacao.ipynb  apresenta os resultados sem poder escrever em producao.

Este modulo apenas os descobre os SQLs do repositório, resolve os marcadores
de ambiente e os submete ao BigQuery.
"""

from __future__ import annotations

import json
import re
from dataclasses import dataclass, asdict, field
from datetime import datetime, timezone
from pathlib import Path

# --------------------------------------------------------------------------
# Localizacao e configuracao
# --------------------------------------------------------------------------

RAIZ = Path(__file__).resolve().parent.parent
CAMADAS = ["setup", "bronze", "silver", "gold", "model"]
DATASETS_PRODUCAO = ("bronze", "silver", "gold")

# Recorte declarado nas queries. Uniforme nos 39 arquivos, o que torna a
# reducao para um unico dia uma substituicao textual unica.
RECORTE_COMPLETO = "DATE '2020-01-01' AND DATE '2020-12-31'"


def carregar_config(caminho=None, permitir_exemplo=False):
    """Le config.env. Formato CHAVE=valor, sem aspas, sem expansao.

    O arquivo real nao vai para o controle de versao: cada integrante do grupo
    aponta para o proprio projeto e a propria conta de faturamento. O que esta
    versionado e o config.env.example, que serve de gabarito.

    `permitir_exemplo` libera o uso do gabarito como fallback. Vale so para a
    verificacao offline, que checa se os marcadores resolvem e nao se importa com
    os valores. Nunca ative isso num caminho que fale com o BigQuery: seria
    apontar para um projeto que nao e o seu.
    """
    caminho = caminho or (RAIZ / "config.env")
    if not caminho.exists() and permitir_exemplo:
        exemplo = RAIZ / "config.env.example"
        if exemplo.exists():
            caminho = exemplo
    if not caminho.exists():
        raise FileNotFoundError(
            "config.env nao encontrado em %s.\n"
            "Copie o gabarito e preencha com os valores do seu ambiente:\n"
            "    cp config.env.example config.env" % caminho
        )
    cfg = {}
    for linha in caminho.read_text(encoding="utf-8").splitlines():
        linha = linha.strip()
        if not linha or linha.startswith("#") or "=" not in linha:
            continue
        chave, valor = linha.split("=", 1)
        cfg[chave.strip()] = valor.strip()
    faltando = [k for k in ("PROJECT_ID", "BUCKET", "LOCATION") if not cfg.get(k)]
    if faltando:
        raise ValueError("config.env incompleto, faltam: %s" % ", ".join(faltando))
    return cfg


# --------------------------------------------------------------------------
# Descoberta das etapas
# --------------------------------------------------------------------------

# O verbo do nome do arquivo diz se a etapa persiste algo. E a mesma convencao
# documentada no README, aqui usada como classificacao executavel.
VERBOS_ESCRITA = {"create", "export", "load", "insert", "clean"}
VERBOS_LEITURA = {"validate", "analyze", "evaluate"}

_PADRAO_NOME = re.compile(r"^(\d{2})-([a-z]+)-(.+)\.sql$")

# Erros de digitacao e formas em portugues que ja apareceram, para que a mensagem
# de erro sugira a correcao em vez de so recusar o arquivo.
_PROXIMO_VERBO = {
    "analize": "analyze", "analise": "analyze", "analyse": "analyze",
    "analitze": "analyze", "evaluation": "evaluate", "evaluete": "evaluate",
    "criacao": "create", "criar": "create", "cria": "create",
    "validacao": "validate", "validte": "validate", "valida": "validate",
    "exporta": "export", "carrega": "load", "insere": "insert",
    "limpa": "clean", "treina": "create",
}


@dataclass(frozen=True)
class Etapa:
    numero: int
    camada: str
    arquivo: str
    verbo: str
    objeto: str

    @property
    def caminho(self):
        return RAIZ / self.camada / self.arquivo

    @property
    def escreve(self):
        return self.verbo in VERBOS_ESCRITA

    @property
    def rotulo(self):
        return "%02d %s" % (self.numero, self.objeto.replace("-", " "))

    def sql_bruto(self):
        return self.caminho.read_text(encoding="utf-8")


def descobrir_etapas():
    """Varre as pastas e devolve as etapas em ordem numerica global.

    Junta todas as violacoes de convencao antes de levantar. Morrer no primeiro
    arquivo malformado esconde os demais e obriga a uma rodada de correcao por
    problema, o que e especialmente ruim aqui: esta funcao e a primeira coisa que
    os dois notebooks chamam, entao um nome errado impede ate a abertura deles.
    """
    etapas, problemas = [], []
    verbos_validos = VERBOS_ESCRITA | VERBOS_LEITURA
    for camada in CAMADAS:
        pasta = RAIZ / camada
        if not pasta.is_dir():
            continue
        for arq in sorted(pasta.glob("*.sql")):
            m = _PADRAO_NOME.match(arq.name)
            if not m:
                problemas.append(
                    "%s/%s foge da convencao NN-verbo-objeto.sql" % (camada, arq.name)
                )
                continue
            numero, verbo, objeto = int(m.group(1)), m.group(2), m.group(3)
            if verbo not in verbos_validos:
                sugestao = _PROXIMO_VERBO.get(verbo)
                problemas.append(
                    "%s/%s: verbo '%s' fora da convencao%s"
                    % (camada, arq.name, verbo,
                       (" (voce quis dizer '%s'?)" % sugestao) if sugestao else "")
                )
                continue
            etapas.append(Etapa(numero, camada, arq.name, verbo, objeto))
    if problemas:
        raise ValueError(
            "%d arquivo(s) fora da convencao de nomes:\n  - %s"
            % (len(problemas), "\n  - ".join(problemas))
        )
    etapas.sort(key=lambda e: e.numero)
    numeros = [e.numero for e in etapas]
    repetidos = sorted({n for n in numeros if numeros.count(n) > 1})
    if repetidos:
        raise ValueError("numeros repetidos entre camadas: %s" % repetidos)
    return etapas


def por_numero(etapas, numero):
    for e in etapas:
        if e.numero == numero:
            return e
    raise KeyError("etapa %s nao encontrada" % numero)


# --------------------------------------------------------------------------
# Resolucao dos marcadores de ambiente
# --------------------------------------------------------------------------

_MARCADOR = re.compile(r"\$\{([A-Z_]+)\}")


def resolver(sql, cfg):
    """Troca ${BUCKET}, ${LOCATION} e ${PROJECT_ID} pelos valores de config.env.

    Falha se sobrar qualquer marcador. Um ${...} nao resolvido chegaria ao
    BigQuery como erro de sintaxe a dezenas de segundos de distancia.
    """
    resolvido = _MARCADOR.sub(lambda m: cfg.get(m.group(1), m.group(0)), sql)
    orfaos = sorted(set(_MARCADOR.findall(resolvido)))
    if orfaos:
        raise ValueError("marcadores sem valor em config.env: %s" % orfaos)
    return resolvido


# --------------------------------------------------------------------------
# Reescrita para a demonstracao ao vivo
# --------------------------------------------------------------------------

_ALVO_CREATE = re.compile(
    r"(CREATE\s+OR\s+REPLACE\s+TABLE\s+`)(" + "|".join(DATASETS_PRODUCAO) + r")(\.)",
    re.IGNORECASE,
)


def reescrever_para_demo(sql, dia, dataset_demo):
    """Reduz uma etapa pesada a um unico dia e desvia a escrita para o dataset de demo.

    Duas substituicoes, ambas textuais e conferiveis a olho na propria celula:

    1. O recorte anual vira um dia. Como as tabelas envolvidas sao particionadas
       por data, o BigQuery le uma particao em vez de 366.
    2. O alvo do CREATE deixa de ser producao. Apenas a primeira ocorrencia e
       trocada, entao as tabelas de origem continuam apontando para os dados
       reais: a demo processa dados de verdade, nao um brinquedo.
    """
    if RECORTE_COMPLETO not in sql:
        raise ValueError("recorte anual nao encontrado; esta etapa nao serve para demo")
    novo = sql.replace(RECORTE_COMPLETO, "DATE '%s' AND DATE '%s'" % (dia, dia))
    novo, trocas = _ALVO_CREATE.subn(r"\1" + dataset_demo + r"\3", novo, count=1)
    if trocas != 1:
        raise ValueError("alvo de escrita nao identificado; esta etapa nao serve para demo")
    return novo


# --------------------------------------------------------------------------
# Guarda de seguranca do notebook de apresentacao
# --------------------------------------------------------------------------

_ESCRITA = re.compile(
    r"\b(CREATE\s+(OR\s+REPLACE\s+)?(TABLE|MODEL|SCHEMA|VIEW)"
    r"|LOAD\s+DATA|EXPORT\s+DATA|INSERT\s+INTO|DELETE\s+FROM|DROP\s+|TRUNCATE\s+TABLE"
    r"|MERGE\s+INTO)\b",
    re.IGNORECASE,
)


def alvos_de_escrita(sql):
    """Onde o SQL escreve. Vazio quando a query e somente leitura.

    EXPORT DATA nao tem alvo em dataset nenhum: ele grava no Cloud Storage. Sem
    um marcador proprio, uma etapa de export passaria despercebida por qualquer
    checagem baseada em nome de dataset, que foi exatamente o furo que a
    verificacao offline encontrou.
    """
    alvos = set()
    if re.search(r"\bEXPORT\s+DATA\b", sql, re.IGNORECASE):
        alvos.add("gs")
    for m in _ESCRITA.finditer(sql):
        trecho = sql[m.start(): m.start() + 400]
        qualificado = re.search(r"`([a-z0-9_]+)\.[a-z0-9_]+`", trecho, re.IGNORECASE)
        if qualificado:
            alvos.add(qualificado.group(1).lower())
        esquema = re.search(
            r"CREATE\s+SCHEMA[^`]*`([a-z0-9_]+)`", trecho, re.IGNORECASE
        )
        if esquema:
            alvos.add(esquema.group(1).lower())
    return alvos


def exigir_somente_leitura(sql, permitidos=()):
    """Levanta se o SQL escreve em qualquer lugar fora de `permitidos`.

    A regra falha fechada: qualquer instrucao de escrita bloqueia, salvo se todo
    alvo identificado estiver liberado. Uma escrita cujo alvo nao foi
    identificado tambem bloqueia -- e mais seguro recusar uma query legitima do
    que deixar passar um EXPORT DATA de um ano inteiro durante a apresentacao.
    """
    if not _ESCRITA.search(sql):
        return
    alvos = alvos_de_escrita(sql)
    proibidos = (alvos - set(permitidos)) if alvos else {"(alvo nao identificado)"}
    if proibidos:
        raise PermissionError(
            "bloqueado: esta query escreve em %s. O notebook de apresentacao le "
            "producao e escreve apenas no dataset de demonstracao. Para executar "
            "de verdade, use notebooks/00-run-pipeline.ipynb."
            % ", ".join(sorted(proibidos))
        )


# --------------------------------------------------------------------------
# Inventario: o que ja existe no projeto
# --------------------------------------------------------------------------

_REFERENCIA = re.compile(
    r"`((?:" + "|".join(DATASETS_PRODUCAO) + r")\.[a-z0-9_]+)`", re.IGNORECASE
)
_CRIACAO = re.compile(
    r"CREATE\s+(?:OR\s+REPLACE\s+)?(?:TABLE|MODEL|VIEW|MATERIALIZED\s+VIEW)"
    r"\s+(?:IF\s+NOT\s+EXISTS\s+)?`([^`]+)`",
    re.IGNORECASE,
)


def objetos_criados(sql):
    """Tabelas e modelos que o SQL produz."""
    return {m.lower() for m in _CRIACAO.findall(sql)}


def objetos_exigidos(sql):
    """Objetos de producao que precisam existir ANTES desta etapa rodar.

    E o conjunto do que ela referencia menos o que ela mesma cria, para que uma
    etapa que le a propria saida nao apareca como dependente de si mesma.
    """
    return {r.lower() for r in _REFERENCIA.findall(sql)} - objetos_criados(sql)


def inventario(cliente, cfg):
    """Tabelas e modelos que existem hoje nos datasets de producao.

    Usa a API de metadados, nao uma query: nao processa bytes e nao gera custo
    nenhum. Isso importa quando o orcamento do projeto acabou e a duvida e
    justamente ate onde o pipeline chegou.
    """
    presentes = set()
    for ds in DATASETS_PRODUCAO:
        ref = "%s.%s" % (cfg["PROJECT_ID"], ds)
        for listar, atributo in ((cliente.list_tables, "table_id"),
                                 (cliente.list_models, "model_id")):
            try:
                for obj in listar(ref):
                    presentes.add("%s.%s" % (ds, getattr(obj, atributo)))
            except Exception:
                pass  # dataset ausente e uma resposta valida: nada foi criado
    return presentes


def diagnostico(etapas, presentes, cfg):
    """Para cada etapa, o que falta para ela poder rodar."""
    linhas = []
    for e in etapas:
        sql = resolver(e.sql_bruto(), cfg)
        exigidos = objetos_exigidos(sql)
        criados = objetos_criados(sql)
        faltando = sorted(exigidos - presentes)
        linhas.append({
            "numero": e.numero,
            "camada": e.camada,
            "arquivo": e.arquivo,
            "materializou": bool(criados) and criados <= presentes,
            "pode_rodar": not faltando,
            "faltando": ", ".join(o.split(".", 1)[1] for o in faltando),
        })
    return linhas


# --------------------------------------------------------------------------
# Manifesto
# --------------------------------------------------------------------------

CAMINHO_MANIFESTO = RAIZ / "notebooks" / "manifesto.json"


@dataclass
class Registro:
    numero: int
    camada: str
    arquivo: str
    verbo: str
    status: str
    job_id: object = None
    inicio: object = None
    fim: object = None
    segundos: object = None
    bytes_faturados: object = None
    slot_ms: object = None
    linhas: object = None
    erro: object = None


def gravar_manifesto(registros, cfg):
    payload = {
        "gerado_em": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "project_id": cfg["PROJECT_ID"],
        "location": cfg["LOCATION"],
        "etapas": [asdict(r) for r in registros],
    }
    CAMINHO_MANIFESTO.write_text(
        json.dumps(payload, indent=2, ensure_ascii=False), encoding="utf-8"
    )
    return CAMINHO_MANIFESTO


def ler_manifesto():
    if not CAMINHO_MANIFESTO.exists():
        return None
    return json.loads(CAMINHO_MANIFESTO.read_text(encoding="utf-8"))


# --------------------------------------------------------------------------
# Formatacao
# --------------------------------------------------------------------------

def humanizar_bytes(n):
    if n is None:
        return "-"
    n = float(n)
    for unidade in ("B", "KB", "MB", "GB", "TB", "PB"):
        if abs(n) < 1024 or unidade == "PB":
            return "%.1f %s" % (n, unidade) if unidade != "B" else "%d B" % n
        n /= 1024.0


def humanizar_segundos(s):
    if s is None:
        return "-"
    if s < 60:
        return "%.1f s" % s
    return "%d min %02d s" % (int(s // 60), int(s % 60))


# --------------------------------------------------------------------------
# Estilo dos graficos
# --------------------------------------------------------------------------

# Paleta de referencia da skill de visualizacao, usada na ordem fixa em que foi
# validada. As cores categoricas so aparecem em pares adjacentes (barras), que e
# a lista de pares para a qual essa ordem foi aprovada.
PALETA = {
    "serie": ["#2a78d6", "#eb6834", "#1baf7a", "#eda100", "#e87ba4",
              "#008300", "#4a3aa7", "#e34948"],
    "superficie": "#fcfcfb",
    "tinta": "#0b0b0b",
    "tinta_secundaria": "#52514e",
    "mudo": "#898781",
    "grade": "#e1e0d9",
    "eixo": "#c3c2b7",
    "divergente": ["#184f95", "#f0efec", "#d03b3b"],
    "critico": "#d03b3b",
}

COR_CAMADA = {
    "setup": PALETA["serie"][0],
    "bronze": PALETA["serie"][1],
    "silver": PALETA["serie"][2],
    "gold": PALETA["serie"][3],
    "model": PALETA["serie"][4],
}


def aplicar_estilo():
    """Configura o matplotlib: marcas finas, grade recessiva, tinta discreta."""
    import matplotlib as mpl

    mpl.rcParams.update({
        "figure.facecolor": PALETA["superficie"],
        "axes.facecolor": PALETA["superficie"],
        "savefig.facecolor": PALETA["superficie"],
        "axes.edgecolor": PALETA["eixo"],
        "axes.labelcolor": PALETA["tinta_secundaria"],
        "axes.titlecolor": PALETA["tinta"],
        "axes.titlesize": 12,
        "axes.titleweight": "semibold",
        "axes.titlelocation": "left",
        "axes.titlepad": 12,
        "axes.labelsize": 9,
        "axes.linewidth": 0.8,
        "axes.spines.top": False,
        "axes.spines.right": False,
        "axes.grid": True,
        "grid.color": PALETA["grade"],
        "grid.linewidth": 0.8,
        "xtick.color": PALETA["mudo"],
        "ytick.color": PALETA["mudo"],
        "xtick.labelsize": 9,
        "ytick.labelsize": 9,
        "legend.frameon": False,
        "legend.fontsize": 9,
        "lines.linewidth": 2.0,
        "lines.markersize": 8,
        "font.size": 10,
        "figure.dpi": 110,
    })


def mapa_divergente():
    """Colormap divergente azul <-> vermelho com meio neutro cinza."""
    from matplotlib.colors import LinearSegmentedColormap

    return LinearSegmentedColormap.from_list("divergente", PALETA["divergente"])
