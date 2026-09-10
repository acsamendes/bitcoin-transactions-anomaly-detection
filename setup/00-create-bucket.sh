#!/usr/bin/env bash
# Pre-requisito do pipeline. Cria a zona de aterrissagem no Cloud Storage usada
# pelos arquivos bronze/03, bronze/04 e bronze/05 (EXPORT DATA) e lida de volta
# por bronze/06 (LOAD DATA FROM FILES).
#
# Os valores vem de config.env na raiz do repositorio. Nenhum nome de projeto ou
# de bucket esta embutido aqui.
#
# A localizacao do bucket precisa ser a mesma dos datasets criados em
# setup/01-create-datasets.sql. O BigQuery recusa EXPORT DATA e LOAD DATA entre
# localizacoes diferentes.
#
# Rodar de novo com o bucket ja existente falha no passo de create com HTTPError
# 409. O erro e inofensivo: o pre-requisito ja esta satisfeito e o pipeline pode
# seguir a partir de setup/01.
#
# Ambiente: bash. No Windows, use Git Bash, WSL ou o Cloud Shell.

set -euo pipefail

CONFIG="$(dirname "$0")/../config.env"

if [ ! -f "${CONFIG}" ] && [ -f "${CONFIG}.example" ]; then
  echo "ERRO: config.env nao existe. Copie o gabarito e preencha:" >&2
  echo "    cp config.env.example config.env" >&2
  exit 1
fi

if [ ! -f "${CONFIG}" ]; then
  echo "ERRO: config.env nao encontrado em ${CONFIG}" >&2
  exit 1
fi

# shellcheck source=../config.env
source "${CONFIG}"

: "${PROJECT_ID:?defina PROJECT_ID em config.env}"
: "${BUCKET:?defina BUCKET em config.env}"
: "${LOCATION:?defina LOCATION em config.env}"

echo "Projeto: ${PROJECT_ID} | Bucket: gs://${BUCKET} | Local: ${LOCATION}"

gcloud config set project "${PROJECT_ID}"

gcloud services enable bigquery.googleapis.com storage.googleapis.com --project="${PROJECT_ID}"

gcloud storage buckets create "gs://${BUCKET}" --project="${PROJECT_ID}" --location="${LOCATION}" --uniform-bucket-level-access

gcloud storage buckets describe "gs://${BUCKET}" --format="value(name,location,storageClass)"
