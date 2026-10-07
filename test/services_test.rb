# frozen_string_literal: true
require_relative 'test_helper'
class ServicesTest < Minitest::Test
  def setup
    @repo = MemoryRepository.new
    @http = FakeHTTP.new(fixture, fixture)
    clients = { 'TRF1' => Tribunais::TRF1::Client.new(http: @http, clock: -> { NOW }), 'STF' => Tribunais::STF::Client.new }
    @now = NOW
    @io = StringIO.new
    @telemetry = Juridico::Telemetry.new(io: @io)
    @service = Services::ProcessoSync.new(resolver: Tribunais::TribunalResolver.new(clients), repository: @repo,
      cache: Services::CacheService.new(ttl: 60, clock: -> { @now }), telemetry: @telemetry)
  end
  def call(tool = 'buscar_processo') = @service.call(ferramenta: tool, numero_cnj: cnj)
  def test_cache_retains_original_consultation_time
    first = call
    @now += 30
    cached = call
    assert_equal 'miss', first['cache']
    assert_equal 'hit', cached['cache']
    assert_equal first['consultado_em'], cached['consultado_em']
    assert_equal 1, @http.calls.size
    assert_equal 1, @repo.audits.size
    assert_includes @telemetry.export, 'cache_hits_total{tribunal="TRF1"} 1'
  end
  def test_expired_cache_and_manual_sync_call_source
    call
    @now += 60
    assert_equal 'miss', call['cache']
    assert_equal 2, @http.calls.size
  end
  def test_force_refresh_bypasses_valid_cache
    call
    assert_equal 'miss', call('sincronizar_processo')['cache']
    assert_equal 2, @repo.audits.size
  end
  def test_movements_tool_uses_same_cache
    call
    result = call('buscar_movimentacoes')
    assert_equal 'hit', result['cache']
    refute result['processos'].first.key?('classe')
    assert_equal 1, result['processos'].first['movimentacoes'].size
  end
  def test_documents_never_claim_empty_success
    error_code('unsupported_capability') { call('buscar_documentos') }
    assert_empty @http.calls
    assert_empty @repo.audits
  end
  def test_stf_does_not_access_repository_or_http
    error_code('unsupported_tribunal') do
      @service.call(ferramenta: 'buscar_processo', numero_cnj: cnj('1','00','0000'))
    end
    assert_empty @repo.audits
  end
  def test_failed_sync_does_not_renew_cache_or_serve_stale
    old = call
    @now += 120
    @http.instance_variable_set(:@responses, [Juridico::Error.new('upstream_timeout', 'Timeout')])
    error_code('upstream_timeout') { call }
    assert_equal 'error', @repo.audits.last[:status]
    assert_equal old['consultado_em'], @repo.data.first['fonte']['consultado_em']
  end
  def test_non_public_response_invalidates_old_cache
    call
    @http.instance_variable_set(:@responses, [Juridico::Error.new('non_public_record', 'Não público')])
    error_code('non_public_record') { call('sincronizar_processo') }
    assert_empty @repo.data
  end
  def test_empty_future_and_malformed_cache_are_not_fresh
    cache = Services::CacheService.new(ttl: 60, clock: -> { NOW })
    refute cache.fresh?([])
    refute cache.fresh?([{}])
    p = canonical
    p['fonte']['consultado_em'] = (NOW + 1).iso8601
    refute cache.fresh?([p])
    refute Services::CacheService.new(ttl: 0).fresh?([canonical])
  end
  def test_logs_have_observability_fields_without_sensitive_data
    call
    row = JSON.parse(@io.string.lines.last)
    %w[tribunal ferramenta duracao status cache http_status].each { |key| assert row.key?(key) }
    @telemetry.record('test', token: 'SECRET', cpf: '12345678900', status: 'ok')
    refute_includes @io.string, 'SECRET'
    refute_includes @io.string, '12345678900'
    refute_includes @io.string, cnj
  end
end
