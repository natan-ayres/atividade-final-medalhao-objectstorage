# Arquitetura de Coleta e Armazenamento de Dados

**Object Storage + Spark com Analytics e IA** · Pós-graduação

Projeto da disciplina: uma arquitetura **Medalhão** (landing, Bronze, Silver e Gold) construída sobre **object storage (MinIO)**, processada com **Spark local** (ou pandas, para quem não conseguir rodar o Spark) e servida ao **Metabase** por um Postgres.
A camada Gold também é preparada para receber, no módulo seguinte, um banco de dados vetorial (o banco vetorial **não** é construído aqui).

Qualidade, observabilidade e governança são ensinadas ao longo de todas as camadas, não só no final.

---

## Arquitetura

```
 data/lote1 ──► LANDING ──► BRONZE ──► SILVER ──► GOLD ──► Postgres ──► Metabase
   (CSV/JSONL)   bucket      Iceberg    Iceberg    Iceberg   schema gold    (BI)
                 landing     (como veio) (limpo,    (negócio)
                                         tipado)       │
                                           │           └──► chunks para IA
                                           ▼                (preparação, módulo seguinte)
                                      QUARENTENA
                                    (o que viola regra)
```

| Camada | O que guarda | Regra principal |
|---|---|---|
| **Landing** | arquivos crus, como a origem enviou | não se altera |
| **Bronze** | dado como veio + colunas de rastreio (`_ingest_ts`, `_source_file`, `_batch_id`) | não se limpa; reexecutar não duplica |
| **Silver** | dado limpo, tipado e deduplicado | o que viola a regra vai para a **quarentena** |
| **Gold** | tabelas de negócio com grão, dono e contrato | só é publicada se passar nos **gates** |

O **lake** (MinIO) é a fonte da verdade. O Postgres e, no futuro, o banco vetorial são cópias derivadas, que podem ser recriadas.

---

## O que você vai aprender

- **Object storage:** buckets, chaves e prefixos ("pastas" não existem), objetos imutáveis, tabela = arquivos de dados + metadados.
- **Spark local + Iceberg:** tabelas sobre o storage, idempotência, histórico de versões (snapshots, `VERSION AS OF`, rollback).
- **Qualidade:** regras explícitas, quarentena, relatório de DQ, reconciliação (entrada = saída + quarentena).
- **Observabilidade:** linhagem, contagens por camada, resultados de qualidade guardados como dado.
- **Governança:** contrato de dados (grão, dono, dicionário), gates de publicação, minimização de dado pessoal, menor privilégio, segredos fora do código.
- **Serviço:** Gold no Postgres e painéis no Metabase com usuário somente leitura.

---

## Estrutura do repositório

> Ajuste esta seção se a sua estrutura for diferente.

```
.
├── README.md
├── requirements.txt
├── docker/
│   ├── docker-compose.yml     # MinIO (e, na aula, Postgres e Metabase)
│   └── .env.example           # copie para .env e ajuste (o .env não vai para o Git)
├── scripts/
│   ├── verifica_ambiente.py   # confere Java, PySpark, Spark e MinIO
│   ├── criar_buckets.py       # cria os buckets landing e warehouse
│   └── preparar_jars.py       # baixa os jars do Spark (Iceberg, S3A) uma vez
├── common/
│   └── lake_local.py          # sessão Spark local + helpers do MinIO
├── winutils/                  # só Windows: winutils.exe e hadoop.dll
├── data/
│   └── lote1/                 # clientes.csv, produtos.csv, pedidos.jsonl, avaliacoes.csv
├── notebooks/                 # liberados ao longo das aulas
│   ├── 01_bronze.ipynb
│   ├── 02_silver.ipynb
│   ├── 03_gold.ipynb
│   ├── 01_bronze_local_pandas.ipynb   # alternativa sem Spark
│   ├── 02_silver_local_pandas.ipynb
│   └── 03_gold_local_pandas.ipynb
└── docs/                      # guias em PDF
```

---

## Pré-requisitos

| Item | Versão | Observação |
|---|---|---|
| Python | **3.11** (aceita 3.10) | evite 3.12/3.13 e o Python da Microsoft Store: causam erros no Spark |
| Java | **17** | JDK, não só o JRE |
| PySpark | 3.5.3 | já traz o Spark; não precisa instalar Spark nem Hadoop à parte |
| Docker | Docker Desktop ou Docker Engine + Compose | para o MinIO |
| Windows | `winutils.exe` e `hadoop.dll` | necessário só no Windows (veja abaixo) |

---

## Preparação do ambiente (antes da aula)

Objetivo: deixar **MinIO e Spark funcionando**. As tabelas e camadas são construídas **em aula**, juntos.

## Gerenciamento de Dependências com uv

Este projeto usa [uv](https://github.com/astral-sh/uv) para gerenciamento de pacotes Python. O uv foi adicionado para substituir o pip tradicional, oferecendo instalações muito mais rápidas e sincronização de ambientes mais confiável.

### Instalação do uv

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

### Sincronização do ambiente

Para instalar todas as dependências listadas no `pyproject.toml` e `uv.lock`:

```bash
uv sync
```

Isso instalará exatamente as versões específicadas e gerará um ambiente isolado em `.venv`. Para ativar o ambiente:

- **Linux/macOS**: `source .venv/bin/activate`
- **Windows PowerShell**: `.venv\Scripts\Activate.ps1`
- **Windows CMD**: `.venv\Scripts\activate.bat`

### Comandos avançados(opcionais)

```bash
# Instalar apenas dependências de desenvolvimento
uv sync --dev

# Atualizar todas as dependências para as versões mais recentes compatíveis
uv lock --upgrade-minor
uv sync

# Gerar um requirements.txt a partir do lockfile
uv pip compile uv.lock -o requirements.txt
```

# Referências

- [Documentação do uv](https://docs.astral.sh/uv/)
- [Guia de migração do pip para uv](https://astral.sh/blog/migrating-from-pip-to-uv)

### 1. Clonar e criar o ambiente Python

**Windows (PowerShell)**
```powershell
git clone <URL-DO-REPOSITORIO>
cd <PASTA-DO-REPOSITORIO>
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
```

**Linux / macOS**
```bash
git clone <URL-DO-REPOSITORIO>
cd <PASTA-DO-REPOSITORIO>
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

### 2. Windows apenas: Hadoop (winutils)

1. Crie a pasta `C:\hadoop\bin` e copie para ela os arquivos da pasta `winutils/` do repositório (`winutils.exe` e `hadoop.dll`).
2. Defina a variável de ambiente `HADOOP_HOME` como `C:\hadoop` e adicione `C:\hadoop\bin` ao `PATH`.
3. **Feche e abra o VS Code por completo** para que ele leia as variáveis novas.

### 3. Subir o MinIO

```bash
cd docker
cp .env.example .env        # Windows: copy .env.example .env
docker compose up -d
cd ..
```

O console do MinIO fica em <http://localhost:9001> (usuário e senha do seu `docker/.env`).

### 4. Criar os buckets e baixar os jars

```bash
python scripts/criar_buckets.py
python scripts/preparar_jars.py      # primeira vez: baixa alguns pacotes, pode demorar
```

### 5. Verificar

```bash
python scripts/verifica_ambiente.py
```

Você deve ver `OK` em todos os itens e `Tudo pronto.` no final. Dentro do Jupyter/VS Code, prefira chamar o script assim, para usar o Python da `.venv` e ver a saída:

```python
import subprocess, sys
r = subprocess.run([sys.executable, "../scripts/verifica_ambiente.py"], capture_output=True, text=True)
print(r.stdout, r.stderr)
```

---

## Problemas comuns

| Sintoma | Causa provável | O que fazer |
|---|---|---|
| `KeyError: 'MINIO_USER'` | `docker/.env` não existe, está no lugar errado ou se chama `.env.txt` | copie `.env.example` para `docker/.env` |
| `HADOOP_HOME and hadoop.home.dir are unset` | winutils não configurado (Windows) | passo 2 e reabrir o VS Code |
| `Python worker failed to connect back` | o Spark não achou o Python da `.venv` | atualize `common/lake_local.py` (versão atual já define `PYSPARK_PYTHON`) e **reinicie o kernel** |
| `Python worker exited unexpectedly (crashed)` | Python 3.12/3.13, Python da Store, pouca RAM, antivírus ou instalação corrompida | use Python 3.11; reinstale `pyspark` |
| `Cannot find catalog plugin class for catalog 'lake'` | o Spark foi iniciado antes dos jars do Iceberg | reinicie o kernel e rode `get_spark()` primeiro; se persistir, apague a pasta `.ivy2` e rode `preparar_jars.py` |
| `Relative path in absolute URI: s3a://warehousebronze` | o warehouse precisa de um prefixo | use `s3a://warehouse/lakehouse` |
| Não consigo rodar o Spark de jeito nenhum | máquina ou ambiente restritos | use os notebooks `*_local_pandas.ipynb` (só pandas + MinIO) |

---

## Notebooks

| Notebook | Tema | Foco |
|---|---|---|
| `01_bronze` | Landing → Bronze | object storage, linhagem, idempotência |
| `02_silver` | Bronze → Silver | regras, quarentena, reconciliação, DQ, histórico de versões |
| `03_gold` | Silver → Gold | contrato, gates, Postgres e Metabase, minimização de dado pessoal; preparação para IA |

Cada um tem uma versão `*_local_pandas`, equivalente, que dispensa Spark e Iceberg (Parquet no MinIO). As diferenças estão descritas no início de cada notebook.

---

## Governança e segurança neste projeto

- **Segredos:** senhas ficam em `docker/.env`, que está no `.gitignore`. O repositório traz apenas o `.env.example`. As senhas de laboratório (`admin12345`, `aula123`) servem **só para este ambiente local**; em produção usam-se cofres de segredos.
- **Menor privilégio:** o Metabase usa um usuário do Postgres com permissão apenas de leitura.
- **Dado pessoal:** nome mascarado e e-mail fora da Gold. Dado pessoal em texto livre é mascarado antes de qualquer uso em IA.
- **Catálogo:** o catálogo Hadoop do Iceberg é adequado para aula. Em produção sobre S3, prefira catálogos gerenciados (Glue, REST, Nessie).

---

## Roteiro

1. **Preparação (em casa):** ambiente, MinIO e Spark funcionando.
2. **Aula 1:** Bronze e object storage.
3. **Aula 2:** Silver, qualidade e histórico de versões.
4. **Aula 3:** Gold, contrato, gates, Postgres e Metabase.
5. **Entrega:** a sua arquitetura (desenho, evidências e decisões).
6. **Módulo seguinte:** embeddings e banco vetorial (pgvector), sobre os chunks preparados na Gold.

---

## Licença

Defina a licença do repositório (por exemplo, MIT) e inclua o arquivo `LICENSE`.

## Autor

Prof. Wuldson Franco

