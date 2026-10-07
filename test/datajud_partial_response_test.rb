# frozen_string_literal: true
require_relative 'test_helper'

class DatajudPartialResponseTest < Minitest::Test
  MESSAGE = 'A fonte respondeu parcialmente e não foi possível validar o resultado.'

  def setup
    @io = StringIO.new
    @telemetry = Juridico::Telemetry.new(io: @io)
    @requests = 0
  end

  def client(data)
    # HTTP real da aplicação com transporte simulado: verifica também ausência de retry.
    config = Juridico::Config.new('DATAJUD_API_KEY' => 'SECRET_TEST_TOKEN')
    http = Juridico::HttpClient.new(config: config, telemetry: @telemetry,
      transport: lambda do |*|
        @requests += 1
        Juridico::HttpClient::Response.new(status: 200, body: JSON.generate(data), headers: {})
      end)
    Tribunais::TRF1::Client.new(http: http, telemetry: @telemetry)
  end

  def response(failed:)
    fixture.tap do |data|
      data['_shards'] = { 'total' => 5, 'successful' => 5 - failed, 'failed' => failed,
        'failures' => [{ 'reason' => 'SECRET_TEST_TOKEN postgresql://PRIVATE CPF 12345678900' }] }
    end
  end

  def test_http_200_without_failed_shards_succeeds
    result = client(response(failed: 0)).buscar_processo(numero_cnj: cnj)
    assert_equal 200, result.http_status
    assert_equal 1, result.processos.size
    assert_equal 1, @requests
    refute_includes @io.string, 'datajud_partial_response'
  end

  def test_http_200_with_failed_shards_is_incomplete_without_retry
    [1, 3].each do |failed|
      before = @requests
      error = error_code('incomplete_response') do
        client(response(failed: failed)).buscar_processo(numero_cnj: cnj)
      end
      assert_equal MESSAGE, error.message
      assert_equal 200, error.http_status
      assert_equal before + 1, @requests
      row = JSON.parse(@io.string.lines.last)
      assert_equal %w[evento tribunal http_status shards_total shards_successful shards_failed duracao].sort, row.keys.sort
      assert_equal 'datajud_partial_response', row['evento']
      assert_equal 'TRF1', row['tribunal']
      assert_equal 200, row['http_status']
      assert_equal 5, row['shards_total']
      assert_equal 5 - failed, row['shards_successful']
      assert_equal failed, row['shards_failed']
      assert_operator row['duracao'], :>=, 0
    end
    %w[SECRET_TEST_TOKEN PRIVATE CPF 12345678900 failures reason numeroProcesso].each do |secret|
      refute_includes @io.string, secret
    end
    assert_includes @telemetry.export, 'tribunal_errors_total{tribunal="TRF1"} 2'
  end

  def test_empty_hits_with_shard_failure_is_never_not_found
    data = response(failed: 1)
    data['hits'] = { 'total' => { 'value' => 0, 'relation' => 'eq' }, 'hits' => [] }
    error = error_code('incomplete_response') { client(data).buscar_processo(numero_cnj: cnj) }
    assert_equal MESSAGE, error.message
    assert_equal 1, @requests
  end

  def test_partial_response_does_not_persist_or_invalidate_existing_cache
    repo = MemoryRepository.new
    previous = [canonical]
    repo.data.concat(previous)
    data = response(failed: 1)
    data['hits'] = { 'total' => { 'value' => 0, 'relation' => 'eq' }, 'hits' => [] }
    service = Services::ProcessoSync.new(
      resolver: Tribunais::TribunalResolver.new('TRF1' => client(data)), repository: repo,
      cache: Services::CacheService.new(ttl: 0), telemetry: @telemetry)
    error_code('incomplete_response') { service.call(ferramenta: 'buscar_processo', numero_cnj: cnj) }
    assert_equal previous, repo.data
    assert_equal 1, repo.audits.size
    assert_equal 'error', repo.audits.first[:status]
    assert_equal 'incomplete_response', repo.audits.first[:error]
  end

  def test_shard_failures_are_checked_before_hits_structure
    data = response(failed: 1)
    data.delete('hits')
    error_code('incomplete_response') { client(data).buscar_processo(numero_cnj: cnj) }
  end

  def test_free_text_in_shard_counts_is_never_logged
    data = response(failed: 1)
    data['_shards']['total'] = 'SECRET_TEST_TOKEN'
    data['_shards']['successful'] = { 'payload' => 'PRIVATE' }
    error_code('incomplete_response') { client(data).buscar_processo(numero_cnj: cnj) }
    row = JSON.parse(@io.string.lines.last)
    assert_nil row['shards_total']
    assert_nil row['shards_successful']
    refute_includes @io.string, 'SECRET_TEST_TOKEN'
    refute_includes @io.string, 'PRIVATE'
  end
end
