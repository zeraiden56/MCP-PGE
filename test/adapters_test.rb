# frozen_string_literal: true
require_relative 'test_helper'
class AdaptersTest < Minitest::Test
  %w[TRF1 TJMT STJ].each do |tribunal|
    define_method("test_#{tribunal.downcase}_client_and_mapper") do
      data = fixture(tribunal)
      http = FakeHTTP.new(data)
      client = Tribunais.const_get(tribunal)::Client.new(http: http, clock: -> { NOW })
      number = data['hits']['hits'][0]['_source']['numeroProcesso']
      result = client.buscar_processo(numero_cnj: number)
      p = result.processos.first
      assert_equal tribunal, p['tribunal_origem']
      assert_equal 'datajud', p['fonte_consulta']
      assert_equal [], p['partes']
      assert_equal [], p['documentos']
      assert_nil p['situacao']
      assert_equal NOW.iso8601(6), p['fonte']['consultado_em']
      assert_equal '2026-01-02T12:00:00', p['data_ajuizamento']
      assert_equal 'Sorteio', p['movimentacoes'][0]['complementos']['tabelados'][0]['nome']
      assert_equal Tribunais::Datajud::Client::ENDPOINTS[tribunal], http.calls[0][:url]
      assert_equal [{ 'term' => { 'nivelSigilo' => 0 } }], http.calls[0][:body]['query']['bool']['filter']
      error_code('unsupported_capability') { client.buscar_documentos(numero_cnj: number) }
      assert_equal 1, http.calls.size
    end
    define_method("test_#{tribunal.downcase}_mapper_rejects_invalid_metadata") do
      data = fixture(tribunal)
      hit = data['hits']['hits'][0]
      number = Tribunais::CNJ.new(hit['_source']['numeroProcesso'])
      hit['_source'].delete('classe')
      error_code('invalid_response') do
        Tribunais.const_get(tribunal)::Mapper.new.map(hit, cnj: number, tribunal: tribunal, url: 'https://example.test', consulted_at: NOW)
      end
    end
  end
  def client_with(data)
    Tribunais::TRF1::Client.new(http: FakeHTTP.new(data), clock: -> { NOW })
  end
  def test_sigilo_and_unknown_sigilo_are_rejected
    [1, '0', nil].each do |level|
      data = fixture
      data['hits']['hits'][0]['_source']['nivelSigilo'] = level
      error_code('non_public_record') { client_with(data).buscar_processo(numero_cnj: cnj) }
    end
  end
  def test_mismatched_number_and_tribunal
    %w[numeroProcesso tribunal].each do |key|
      data = fixture
      data['hits']['hits'][0]['_source'][key] = 'divergente'
      error_code('invalid_response') { client_with(data).buscar_processo(numero_cnj: cnj) }
    end
  end
  def test_partial_and_malformed_results
    data = fixture
    data['timed_out'] = true
    error_code('incomplete_response') { client_with(data).buscar_processo(numero_cnj: cnj) }
    data = fixture
    data['_shards']['failed'] = 1
    error_code('incomplete_response') { client_with(data).buscar_processo(numero_cnj: cnj) }
    error_code('invalid_response') { client_with({}).buscar_processo(numero_cnj: cnj) }
    data = fixture
    data['hits']['total']['relation'] = 'gte'
    error_code('invalid_response') { client_with(data).buscar_processo(numero_cnj: cnj) }
  end
  def test_not_found
    data = fixture
    data['hits'] = { 'total' => { 'value' => 0, 'relation' => 'eq' }, 'hits' => [] }
    error_code('not_found') { client_with(data).buscar_processo(numero_cnj: cnj) }
  end
  def test_preserves_multiple_covers_and_deduplicates_movements
    data = fixture
    first = data['hits']['hits'].first
    first['_source']['movimentos'] *= 2
    second = Marshal.load(Marshal.dump(first))
    second['_id'] = second['_source']['id'] = 'TRF1_G2_SYNTHETIC'
    second['_source']['grau'] = 'G2'
    data['hits']['hits'] << second
    data['hits']['total']['value'] = 2
    p = client_with(data).buscar_processo(numero_cnj: cnj).processos
    assert_equal %w[G1 G2], p.map { |item| item['grau'] }
    assert_equal [1, 1], p.map { |item| item['movimentacoes'].size }
  end
  def test_pagination
    first, second = fixture, fixture
    [first, second].each { |d| d['hits']['total']['value'] = 2 }
    second['hits']['hits'][0]['_id'] = second['hits']['hits'][0]['_source']['id'] = 'second'
    http = FakeHTTP.new(first, second)
    result = Tribunais::TRF1::Client.new(http: http).buscar_processo(numero_cnj: cnj)
    assert_equal 2, result.processos.size
    assert_equal [0, 100], http.calls.map { |c| c[:body]['from'] }
  end
  def test_repeated_page_is_not_cached_as_complete
    first = fixture
    first['hits']['total']['value'] = 2
    client = Tribunais::TRF1::Client.new(http: FakeHTTP.new(first, first))
    error_code('incomplete_response') { client.buscar_processo(numero_cnj: cnj) }
  end
  def test_stf_is_explicitly_unsupported
    client = Tribunais::STF::Client.new
    assert_equal 'unsupported', client.capabilities['status']
    %i[buscar_processo buscar_movimentacoes buscar_documentos].each do |method|
      error_code('unsupported_tribunal') { client.public_send(method, numero_cnj: cnj('1','00','0000')) }
    end
    error_code('unsupported_tribunal') { Tribunais::STF::Mapper.new.map({}) }
  end
end
class AdapterAdditionalTest < Minitest::Test
  %w[TRF1 TJMT STJ].each do |tribunal|
    define_method("test_#{tribunal.downcase}_propagates_transport_error") do
      data = fixture(tribunal)
      number = data['hits']['hits'][0]['_source']['numeroProcesso']
      %w[upstream_timeout upstream_http_error invalid_response].each do |code|
        client = Tribunais.const_get(tribunal)::Client.new(http: FakeHTTP.new(Juridico::Error.new(code, 'Erro sintético')))
        error_code(code) { client.buscar_processo(numero_cnj: number) }
      end
    end
    define_method("test_#{tribunal.downcase}_movement_interface") do
      data = fixture(tribunal)
      number = data['hits']['hits'][0]['_source']['numeroProcesso']
      client = Tribunais.const_get(tribunal)::Client.new(http: FakeHTTP.new(data))
      output = client.buscar_movimentacoes(numero_cnj: number)
      assert_equal 1, output.size
      assert_equal 1, output.first['movimentacoes'].size
      assert output.first['fonte']['consultado_em']
    end
  end
  def test_duplicate_canonical_ids_are_rejected_even_with_different_search_ids
    data = fixture
    copy = Marshal.load(Marshal.dump(data['hits']['hits'][0]))
    copy['_id'] = 'another-search-id'
    data['hits']['hits'] << copy
    data['hits']['total']['value'] = 2
    client = Tribunais::TRF1::Client.new(http: FakeHTTP.new(data))
    error_code('invalid_response') { client.buscar_processo(numero_cnj: cnj) }
  end
end
