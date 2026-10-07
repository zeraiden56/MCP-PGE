-- Schema privado: não incluir em exposed schemas do Supabase/PostgREST.
CREATE SCHEMA IF NOT EXISTS juridico;
REVOKE ALL ON SCHEMA juridico FROM PUBLIC;

CREATE TABLE juridico.processos (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  numero_cnj TEXT NOT NULL,
  numero_cnj_normalizado TEXT NOT NULL CHECK (numero_cnj_normalizado ~ '^[0-9]{20}$'),
  tribunal TEXT NOT NULL,
  tribunal_origem TEXT NOT NULL,
  id_origem TEXT NOT NULL,
  grau TEXT,
  classe TEXT,
  assuntos JSONB NOT NULL DEFAULT '[]',
  orgao_julgador TEXT,
  -- Datas de origem conservam offset/ausência de fuso sem inventar timezone.
  data_ajuizamento TEXT,
  situacao TEXT,
  fonte_consulta TEXT NOT NULL,
  ultima_consulta_em TIMESTAMPTZ NOT NULL,
  snapshot JSONB NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (numero_cnj_normalizado, tribunal, id_origem)
);
CREATE INDEX processos_numero_cnj_idx ON juridico.processos (numero_cnj_normalizado);
CREATE TABLE juridico.partes (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  chave_deduplicacao TEXT NOT NULL UNIQUE,
  nome TEXT NOT NULL,
  documento TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE juridico.processo_partes (
  processo_id BIGINT NOT NULL REFERENCES juridico.processos ON DELETE CASCADE,
  parte_id BIGINT NOT NULL REFERENCES juridico.partes,
  polo TEXT NOT NULL DEFAULT '',
  tipo TEXT NOT NULL DEFAULT '',
  PRIMARY KEY (processo_id, parte_id, polo, tipo)
);
CREATE TABLE juridico.movimentacoes (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  processo_id BIGINT NOT NULL REFERENCES juridico.processos ON DELETE CASCADE,
  codigo_externo TEXT,
  descricao TEXT NOT NULL,
  data_movimentacao TEXT NOT NULL,
  payload_origem JSONB NOT NULL DEFAULT '{}',
  fingerprint TEXT NOT NULL,
  UNIQUE (processo_id, fingerprint)
);
CREATE TABLE juridico.documentos (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  processo_id BIGINT NOT NULL REFERENCES juridico.processos ON DELETE CASCADE,
  identificador_externo TEXT NOT NULL,
  tipo TEXT,
  descricao TEXT,
  data_documento TEXT,
  url_origem TEXT,
  metadata JSONB NOT NULL DEFAULT '{}',
  UNIQUE (processo_id, identificador_externo)
);
CREATE TABLE juridico.fontes_consulta (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  processo_id BIGINT NOT NULL REFERENCES juridico.processos ON DELETE CASCADE,
  sistema TEXT NOT NULL,
  url_origem TEXT NOT NULL,
  consultado_em TIMESTAMPTZ NOT NULL,
  payload_bruto JSONB,
  hash_resposta TEXT NOT NULL,
  UNIQUE (processo_id, sistema)
);
CREATE TABLE juridico.sincronizacoes (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  processo_id BIGINT REFERENCES juridico.processos ON DELETE SET NULL,
  numero_cnj_normalizado TEXT NOT NULL,
  tribunal TEXT NOT NULL,
  fonte TEXT NOT NULL,
  iniciada_em TIMESTAMPTZ NOT NULL DEFAULT now(),
  finalizada_em TIMESTAMPTZ,
  status TEXT NOT NULL CHECK (status IN ('running', 'success', 'error')),
  http_status INTEGER,
  mensagem_erro TEXT,
  hash_resposta TEXT
);
CREATE INDEX sincronizacoes_numero_idx ON juridico.sincronizacoes (numero_cnj_normalizado, iniciada_em DESC);
REVOKE ALL ON ALL TABLES IN SCHEMA juridico FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA juridico FROM PUBLIC;
