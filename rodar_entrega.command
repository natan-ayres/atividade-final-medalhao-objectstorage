#!/bin/bash
# Sobe MinIO + Postgres + Metabase (docker compose) e executa os notebooks pandas 01, 02 e 03.
cd "$(dirname "$0")"
exec > >(tee run_log.txt) 2>&1
set -e
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.docker/bin:$HOME/.orbstack/bin:$PATH"
echo "== Docker"
echo "docker: $(command -v docker || echo NAO ENCONTRADO) | colima: $(command -v colima || echo nao) | podman: $(command -v podman || echo nao)"
if ! docker info >/dev/null 2>&1; then
  if command -v colima >/dev/null; then colima start --cpu 2 --memory 4 || true
  else open -a Docker 2>/dev/null || open -a OrbStack 2>/dev/null || true; fi
  for i in $(seq 1 60); do docker info >/dev/null 2>&1 && break; echo "aguardando Docker..."; sleep 3; done
fi
docker info >/dev/null
# Senhas de LABORATÓRIO (as mesmas do kit). Se existir docker/.env, ele tem prioridade.
export MINIO_USER=admin MINIO_PASSWORD=admin12345 PG_USER=aula PG_PASSWORD=aula123 PG_PORT=5433
[ -f docker/.env ] && { set -a; . docker/.env; set +a; }
( cd docker && docker compose up -d )
echo "== aguardando MinIO e Postgres"
for i in $(seq 1 60); do curl -sf http://localhost:9000/minio/health/live >/dev/null && break; sleep 2; done
for i in $(seq 1 60); do (cd docker && docker compose exec -T postgres pg_isready -U "$PG_USER" -d serving) >/dev/null 2>&1 && break; sleep 2; done
(cd docker && docker compose ps)
echo "== Python"
PY=""
for c in python3.11 python3.12 python3.10 python3.13 python3; do command -v $c >/dev/null && { PY=$c; break; }; done
echo "usando $PY ($($PY --version))"
[ -d .venv ] || $PY -m venv .venv
. .venv/bin/activate
pip install -q --upgrade pip
pip install -q "pandas>=2.2,<3" "pyarrow>=16" boto3 sqlalchemy psycopg2-binary matplotlib nbconvert nbclient ipykernel
export MINIO_ENDPOINT=http://localhost:9000 MINIO_USER MINIO_PASSWORD
export POSTGRES_HOST=localhost POSTGRES_PORT=$PG_PORT POSTGRES_DB=serving POSTGRES_USER=$PG_USER POSTGRES_PASSWORD=$PG_PASSWORD
echo "== Notebooks"
for nb in 01_bronze_local_pandas 02_silver_local_pandas 03_gold_local_pandas; do
  echo "-- $nb"
  jupyter nbconvert --to notebook --execute --inplace --ExecutePreprocessor.timeout=1200 "notebooks_pandas/$nb.ipynb"
done
echo "== FIM OK $(date)"
echo "Metabase: http://localhost:3000"
