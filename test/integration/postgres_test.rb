# frozen_string_literal: true
require_relative '../test_helper'
require_relative '../../db/migrate'
class PostgresTest < Minitest::Test
  def setup
    skip 'Defina TEST_DATABASE_URL para um banco descartável terminado em _test.' if ENV.fetch('TEST_DATABASE_URL', '').empty?
    @conn = PG.connect(ENV.fetch('TEST_DATABASE_URL'))
    unless @conn.db.end_with?('_test')
      @conn.close
      raise 'Recusando testes destrutivos: nome do banco deve terminar em _test.'
    end
    @conn.set_notice_processor { |_message| }
    Database.migrate(@conn)
    @conn.exec('TRUNCATE juridico.processos, juridico.partes, juridico.sincronizacoes RESTART IDENTITY CASCADE')
    @repo = Repositories::ProcessoRepository.new(database_url: nil, connection: @conn, store_raw: true)
  end
  def teardown
    @conn&.close unless @conn&.finished?
  end
  def result(processes = [canonical])
    Tribunais::FetchResult.new(processos: processes, raw: fixture, http_status: 200)
  end
  def save(value = result)
    id = @repo.start_sync(numero: cnj, tribunal: 'TRF1', fonte: 'datajud')
    @repo.save(value, sync_id: id)
    id
  end
  def count(table) = @conn.exec("SELECT count(*) FROM juridico.#{table}").getvalue(0, 0).to_i
  def test_migrations_are_idempotent
    Database.migrate(@conn)
    assert_equal 1, count('schema_migrations')
    assert_equal 0, count('processos')
  end
  def test_roundtrip_all_tables_and_deduplication
    p = canonical
    p['partes'] = [Schemas::Parte.new(nome: 'Pessoa sintética', tipo: 'requerente', polo: 'ativo', documento: nil).to_h] * 2
    p['documentos'] = [Schemas::Documento.new(id_externo: 'fake-1', tipo: 'decisao', descricao: 'Fictício', data: '2026-01-02', url: nil).to_h] * 2
    p['movimentacoes'] *= 2
    2.times { save(result([p])) }
    assert_equal 1, count('processos')
    assert_equal 1, count('partes')
    assert_equal 1, count('processo_partes')
    assert_equal 1, count('movimentacoes')
    assert_equal 1, count('documentos')
    assert_equal 1, count('fontes_consulta')
    assert_equal 2, count('sincronizacoes')
    assert_equal [p], @repo.find(numero: cnj, tribunal: 'TRF1')
    row = @conn.exec('SELECT * FROM juridico.sincronizacoes ORDER BY id DESC LIMIT 1').first
    assert_equal 'success', row['status']
    assert_equal '200', row['http_status']
    assert_match(/\A[0-9a-f]{64}\z/, row['hash_resposta'])
    assert @conn.exec('SELECT payload_bruto FROM juridico.fontes_consulta').first['payload_bruto']
  end
  def test_multiple_covers_and_removal_of_old_cover
    a, b = canonical, canonical
    b['id_origem'], b['grau'] = 'second', 'G2'
    save(result([a, b]))
    assert_equal 2, count('processos')
    assert_equal 2, count('movimentacoes')
    save(result([b]))
    assert_equal 1, count('processos')
    assert_equal 1, count('movimentacoes')
    assert_equal 'G2', @repo.find(numero: cnj, tribunal: 'TRF1').first['grau']
  end
  def test_transaction_rolls_back_all_changes
    save
    p = canonical
    p['classe'] = 'Não deve persistir'
    p['documentos'] = [{ 'id_externo' => nil }]
    sync_id = @repo.start_sync(numero: cnj, tribunal: 'TRF1', fonte: 'datajud')
    error = error_code('database_error') { @repo.save(result([p]), sync_id: sync_id) }
    @repo.fail_sync(sync_id, error)
    assert_equal canonical['classe'], @repo.find(numero: cnj, tribunal: 'TRF1').first['classe']
    assert_equal 1, count('movimentacoes')
    assert_equal 'error', @conn.exec('SELECT status FROM juridico.sincronizacoes ORDER BY id DESC LIMIT 1').getvalue(0,0)
  end
  def test_no_result_attempt_has_audit_without_process
    id = @repo.start_sync(numero: cnj, tribunal: 'TRF1', fonte: 'datajud')
    @repo.fail_sync(id, Juridico::Error.new('upstream_http_error', 'SECRET must not persist', http_status: 503))
    row = @conn.exec('SELECT * FROM juridico.sincronizacoes').first
    assert_nil row['processo_id']
    assert_equal '503', row['http_status']
    assert_equal 'upstream_http_error', row['mensagem_erro']
    refute_includes row.values.join, 'SECRET'
  end
  def test_advisory_lock_prevents_duplicate_parallel_fetch
    conn2 = PG.connect(ENV.fetch('TEST_DATABASE_URL'))
    other = Repositories::ProcessoRepository.new(database_url: nil, connection: conn2)
    @repo.with_lock('TRF1:test') do
      error_code('sync_busy') { other.with_lock('TRF1:test') { flunk 'Lock duplicado' } }
    end
    assert_equal :ok, other.with_lock('TRF1:test') { :ok }
  ensure
    conn2&.close
  end
  def test_default_raw_payload_storage_is_disabled
    repo = Repositories::ProcessoRepository.new(database_url: nil, connection: @conn)
    id = repo.start_sync(numero: cnj, tribunal: 'TRF1', fonte: 'datajud')
    repo.save(result, sync_id: id)
    assert_nil @conn.exec('SELECT payload_bruto FROM juridico.fontes_consulta').getvalue(0,0)
  end
  def test_end_to_end_service_uses_postgres_cache
    http = FakeHTTP.new(fixture, fixture)
    service = Services::ProcessoSync.new(resolver: Tribunais::TribunalResolver.new('TRF1' => Tribunais::TRF1::Client.new(http: http, clock: -> { NOW })),
      repository: @repo, cache: Services::CacheService.new(ttl: 60, clock: -> { NOW }), telemetry: telemetry)
    first = service.call(ferramenta: 'buscar_processo', numero_cnj: cnj)
    cached = service.call(ferramenta: 'buscar_movimentacoes', numero_cnj: cnj)
    assert_equal 'hit', cached['cache']
    assert_equal first['consultado_em'], cached['consultado_em']
    assert_equal 1, http.calls.size
    service.call(ferramenta: 'sincronizar_processo', numero_cnj: cnj)
    assert_equal 2, http.calls.size
    assert_equal 1, count('movimentacoes')
  end
end
