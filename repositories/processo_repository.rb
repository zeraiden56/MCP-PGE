# frozen_string_literal: true
require 'pg'
require 'digest'
require 'monitor'
module Repositories
  class ProcessoRepository
    def initialize(database_url:, connection: nil, store_raw: false)
      @conn = connection || PG.connect(database_url, connect_timeout: 5)
      @conn.exec("SET statement_timeout = '30s'")
      @conn.exec("SET lock_timeout = '5s'")
      @mutex, @store_raw = Monitor.new, store_raw
    rescue PG::Error
      raise Juridico::Error.new('database_error', 'Não foi possível conectar ao PostgreSQL.')
    end

    def with_lock(key)
      @mutex.synchronize do
        locked = query('SELECT pg_try_advisory_lock(hashtextextended($1,0)) AS locked', [key]).first['locked'] == 't'
        raise Juridico::Error.new('sync_busy', 'Já existe uma consulta em andamento para este processo.') unless locked
        begin
          yield
        ensure
          query('SELECT pg_advisory_unlock(hashtextextended($1,0))', [key])
        end
      end
    end

    def find(numero:, tribunal:)
      query('SELECT snapshot FROM juridico.processos WHERE numero_cnj_normalizado=$1 AND tribunal=$2 ORDER BY id_origem',
            [numero, tribunal]).map { |row| JSON.parse(row['snapshot']) }
    end

    def start_sync(numero:, tribunal:, fonte:)
      query("INSERT INTO juridico.sincronizacoes(numero_cnj_normalizado, tribunal, fonte, status) VALUES ($1,$2,$3,'running') RETURNING id",
            [numero, tribunal, fonte]).first['id']
    end

    def fail_sync(id, error)
      query("UPDATE juridico.sincronizacoes SET finalizada_em=now(), status='error', http_status=$2, mensagem_erro=$3 WHERE id=$1",
            [id, error.respond_to?(:http_status) ? error.http_status : nil,
             error.respond_to?(:code) ? error.code : 'internal_error'])
    end

    def save(result, sync_id:)
      @mutex.synchronize do
        @conn.transaction do
          hash = fingerprint(result.raw)
          ids = result.processos.map { |p| save_process(p, result.raw, hash) }
          sample = result.processos.fetch(0)
          number = Tribunais::CNJ.new(sample.fetch('numero_cnj')).normalizado
          # Snapshot completo confirmado: remover capas que deixaram de ser públicas/indexadas.
          query('DELETE FROM juridico.processos WHERE numero_cnj_normalizado=$1 AND tribunal=$2 AND NOT (id = ANY($3::bigint[]))',
                [number, sample.fetch('tribunal'), "{#{ids.join(',')}}"])
          query('DELETE FROM juridico.partes WHERE NOT EXISTS (SELECT 1 FROM juridico.processo_partes pp WHERE pp.parte_id=partes.id)')
          query("UPDATE juridico.sincronizacoes SET processo_id=$2, finalizada_em=now(), status='success', http_status=$3, hash_resposta=$4 WHERE id=$1",
                [sync_id, ids.first, result.http_status, hash])
        end
      end
      result.processos
    rescue PG::Error
      raise Juridico::Error.new('database_error', 'Falha ao persistir consulta; transação revertida.')
    end

    def invalidate(numero:, tribunal:)
      query('DELETE FROM juridico.processos WHERE numero_cnj_normalizado=$1 AND tribunal=$2', [numero, tribunal])
    end

    def close = @conn.close

    private

    def query(sql, params = [])
      @mutex.synchronize { @conn.exec_params(sql, params) }
    rescue PG::Error
      raise Juridico::Error.new('database_error', 'Operação PostgreSQL falhou.')
    end
    def fingerprint(value)
      Digest::SHA256.hexdigest(JSON.generate(canonical(value)))
    end
    def canonical(value)
      case value
      when Hash then value.sort.to_h.transform_values { |v| canonical(v) }
      when Array then value.map { |v| canonical(v) }
      else value
      end
    end
    def save_process(p, raw, hash)
      number = Tribunais::CNJ.new(p.fetch('numero_cnj')).normalizado
      sql = <<~SQL
        INSERT INTO juridico.processos(numero_cnj,numero_cnj_normalizado,tribunal,tribunal_origem,id_origem,grau,classe,assuntos,
          orgao_julgador,data_ajuizamento,situacao,fonte_consulta,ultima_consulta_em,snapshot)
        VALUES ($1,$2,$3,$4,$5,$6,$7,$8::jsonb,$9,$10,$11,$12,$13,$14::jsonb)
        ON CONFLICT(numero_cnj_normalizado,tribunal,id_origem) DO UPDATE SET
          grau=excluded.grau,classe=excluded.classe,assuntos=excluded.assuntos,orgao_julgador=excluded.orgao_julgador,
          data_ajuizamento=excluded.data_ajuizamento,situacao=excluded.situacao,ultima_consulta_em=excluded.ultima_consulta_em,
          snapshot=excluded.snapshot,updated_at=now()
        RETURNING id
      SQL
      id = query(sql, [p['numero_cnj'], number, p['tribunal'], p['tribunal_origem'], p['id_origem'], p['grau'], p['classe'],
        JSON.generate(p['assuntos']), p['orgao_julgador'], p['data_ajuizamento'], p['situacao'], p['fonte_consulta'],
        p.fetch('fonte').fetch('consultado_em'), JSON.generate(p)]).first['id']
      query('DELETE FROM juridico.movimentacoes WHERE processo_id=$1', [id])
      p.fetch('movimentacoes').each do |m|
        query('INSERT INTO juridico.movimentacoes(processo_id,codigo_externo,descricao,data_movimentacao,payload_origem,fingerprint) VALUES ($1,$2,$3,$4,$5::jsonb,$6) ON CONFLICT DO NOTHING',
              [id, m['codigo'], m['descricao'], m['data'], JSON.generate(m), fingerprint(m)])
      end
      query('DELETE FROM juridico.documentos WHERE processo_id=$1', [id])
      p.fetch('documentos').each do |d|
        query('INSERT INTO juridico.documentos(processo_id,identificador_externo,tipo,descricao,data_documento,url_origem,metadata) VALUES ($1,$2,$3,$4,$5,$6,$7::jsonb) ON CONFLICT DO NOTHING',
              [id, d['id_externo'], d['tipo'], d['descricao'], d['data'], d['url'], JSON.generate(d)])
      end
      query('DELETE FROM juridico.processo_partes WHERE processo_id=$1', [id])
      p.fetch('partes').each do |part|
        # Sem documento, nome não basta para vincular pessoas entre processos.
        key = fingerprint([id, part['nome'], part['documento']])
        part_id = query('INSERT INTO juridico.partes(chave_deduplicacao,nome,documento) VALUES ($1,$2,$3) ON CONFLICT(chave_deduplicacao) DO UPDATE SET updated_at=now() RETURNING id',
                        [key, part['nome'], part['documento']]).first['id']
        query('INSERT INTO juridico.processo_partes(processo_id,parte_id,polo,tipo) VALUES ($1,$2,$3,$4) ON CONFLICT DO NOTHING',
              [id, part_id, part['polo'] || '', part['tipo'] || ''])
      end
      query('INSERT INTO juridico.fontes_consulta(processo_id,sistema,url_origem,consultado_em,payload_bruto,hash_resposta) VALUES ($1,$2,$3,$4,$5::jsonb,$6) ON CONFLICT(processo_id,sistema) DO UPDATE SET consultado_em=excluded.consultado_em,payload_bruto=excluded.payload_bruto,hash_resposta=excluded.hash_resposta,url_origem=excluded.url_origem',
            [id, p['fonte_consulta'], p['fonte']['url_origem'], p['fonte']['consultado_em'], @store_raw ? JSON.generate(raw) : nil, hash])
      id
    end
  end
end
