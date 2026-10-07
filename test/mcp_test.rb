# frozen_string_literal: true
require_relative 'test_helper'
class MCPTest < Minitest::Test
  def setup
    @http = FakeHTTP.new(fixture, fixture)
    @service = Services::ProcessoSync.new(
      resolver: Tribunais::TribunalResolver.new('TRF1' => Tribunais::TRF1::Client.new(http: @http, clock: -> { NOW }), 'STF' => Tribunais::STF::Client.new),
      repository: MemoryRepository.new, cache: Services::CacheService.new(ttl: 60, clock: -> { NOW }), telemetry: telemetry)
    @server = Juridico.server(service: @service)
  end
  def rpc(method, params = {})
    JSON.parse(@server.handle_json(JSON.generate(jsonrpc: '2.0', id: 1, method: method, params: params)))
  end
  def tool(name, arguments = { 'numero_cnj' => cnj })
    rpc('tools/call', 'name' => name, 'arguments' => arguments)
  end
  def test_initialize_and_list
    init = rpc('initialize', 'protocolVersion' => '2025-11-25', 'capabilities' => {}, 'clientInfo' => { 'name' => 'test', 'version' => '1' })
    assert_equal 'mcp-juridico', init.dig('result', 'serverInfo', 'name')
    names = rpc('tools/list').dig('result', 'tools').map { |t| t['name'] }
    assert_equal %w[buscar_documentos buscar_movimentacoes buscar_processo sincronizar_processo], names.sort
  end
  def test_process_movements_and_sync_via_json_rpc
    %w[buscar_processo buscar_movimentacoes sincronizar_processo].each do |name|
      response = tool(name)
      refute response.dig('result', 'isError'), response.inspect
      structured = response.dig('result', 'structuredContent')
      assert_equal 'ok', structured['status']
      assert_equal NOW.iso8601(6), structured['consultado_em']
    end
    assert_equal 2, @http.calls.size
  end
  def test_unsupported_is_tool_error
    response = tool('buscar_documentos')
    assert_equal true, response.dig('result', 'isError')
    assert_equal 'unsupported_capability', response.dig('result', 'structuredContent', 'code')
  end
  def test_bad_number_is_tool_error
    response = tool('buscar_processo', 'numero_cnj' => '00000000000000000000')
    assert_equal 'invalid_cnj', response.dig('result', 'structuredContent', 'code')
    assert_empty @http.calls
  end
  def test_schema_and_unknown_tool_errors
    [{}, { 'numero_cnj' => 123 }, { 'numero_cnj' => cnj, 'tribunal' => 'STF' }].each do |args|
      response = tool('buscar_processo', args)
      assert(response.key?('error') || response.dig('result', 'isError'), response.inspect)
    end
    assert tool('buscar_processo_trf1').key?('error')
  end
  def test_internal_errors_do_not_leak_secrets
    service = Object.new
    def service.call(**) = raise('postgres://user:SECRET@host CPF 12345678900')
    @server = Juridico.server(service: service)
    response = tool('buscar_processo')
    assert_equal 'internal_error', response.dig('result', 'structuredContent', 'code')
    refute_includes JSON.generate(response), 'SECRET'
    refute_includes JSON.generate(response), '12345678900'
  end
end
