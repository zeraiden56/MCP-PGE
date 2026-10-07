# frozen_string_literal: true
require_relative 'test_helper'
require 'minitest/mock'
load File.expand_path('../bin/smoke_datajud', __dir__)

class SmokeDatajudTest < Minitest::Test
  class Repository < TestData::MemoryRepository
    attr_reader :closes
    attr_accessor :close_error
    def close
      @closes = (@closes || 0) + 1
      raise close_error if close_error
    end
  end

  def run_smoke(args = [cnj])
    @out, @err = StringIO.new, StringIO.new
    Juridico::SmokeDatajud.run(args, out: @out, err: @err)
  end

  def test_real_composition_without_mcp_and_cache_roundtrip
    repo = Repository.new
    data = fixture
    second = Marshal.load(Marshal.dump(data['hits']['hits'].first))
    second['_id'] = second['_source']['id'] = 'second-cover'
    second['_source']['grau'] = 'G2'
    data['hits']['hits'] << second
    data['hits']['total']['value'] = 2
    http = FakeHTTP.new(data)
    config = Juridico::Config.new('DATABASE_URL' => 'synthetic-test-url')
    Juridico.stub(:server, ->(**) { flunk 'O smoke não deve construir servidor MCP' }) do
      Juridico::Config.stub(:new, config) do
        Juridico::Telemetry.stub(:new, telemetry) do
          Juridico::HttpClient.stub(:new, http) do
            Repositories::ProcessoRepository.stub(:new, repo) do
              assert_equal 0, run_smoke
              first = JSON.parse(@out.string)
              assert_equal 'miss', first['cache']
              assert_equal 2, first['processos_encontrados']
              assert_equal 2, first['movimentacoes_encontradas']
              assert_equal 'TRF1', first['tribunal']
              assert_equal 'datajud', first['fonte']
              assert_equal 'ok', first['status']
              assert first['consultado_em']
              assert_operator first['duracao_segundos'], :>=, 0
              refute_includes @out.string, 'Unidade fictícia'
              assert_empty @err.string
              assert_equal 'success', repo.audits.first[:status]
              assert_equal 0, run_smoke
              assert_equal 'hit', JSON.parse(@out.string)['cache']
              assert_equal 1, http.calls.size
              assert_equal 2, repo.closes
            end
          end
        end
      end
    end
  end

  def test_mcp_build_preserves_contract_and_uses_same_service
    service, repo, server = Object.new, Object.new, Object.new
    config = Juridico::Config.new({})
    Juridico.stub(:build_service, ->(config:) { assert_instance_of Juridico::Config, config; [service, repo] }) do
      Juridico.stub(:server, ->(**args) { assert_same service, args.fetch(:service); server }) do
        assert_equal [server, repo], Juridico.build(config: config)
      end
    end
  end

  def test_usage_does_not_build_dependencies
    Juridico.stub(:build_service, -> { flunk 'Não deve construir dependências' }) do
      [[], [' '], [cnj, 'extra']].each do |args|
        assert_equal 1, run_smoke(args)
        assert_empty @out.string
        assert_match(/Uso:/, @err.string)
      end
    end
  end

  def test_errors_are_sanitized_and_repository_is_closed
    [Juridico::Error.new('database_error', 'postgresql://user:SECRET@host CPF 12345678900'),
     RuntimeError.new('APIKey SECRET payload: Pessoa identificável')].each do |error|
      repo = Repository.new
      service = Minitest::Mock.new
      service.expect(:call, nil) do |**args|
        assert_equal({ ferramenta: 'buscar_processo', numero_cnj: cnj }, args)
        raise error
      end
      Juridico.stub(:build_service, [service, repo]) do
        assert_equal 1, run_smoke
        assert_empty @out.string
        result = JSON.parse(@err.string)
        assert_equal error.class.name, result['error_class']
        assert_equal 'database_error', result['code'] if error.is_a?(Juridico::Error)
        %w[SECRET postgresql CPF payload Pessoa].each { |secret| refute_includes @err.string, secret }
        assert_equal 1, repo.closes
      end
      service.verify
    end
  end

  def test_build_failure_is_sanitized
    Juridico.stub(:build_service, -> { raise ArgumentError, 'DATABASE_URL=SECRET' }) do
      assert_equal 1, run_smoke
      assert_equal 'ArgumentError', JSON.parse(@err.string)['error_class']
      refute_includes @err.string, 'SECRET'
    end
  end

  def test_close_error_does_not_hide_original_failure
    repo = Repository.new
    repo.close_error = RuntimeError.new('SECRET')
    service = Object.new
    def service.call(**) = raise(Juridico::Error.new('upstream_timeout', 'SECRET'))
    Juridico.stub(:build_service, [service, repo]) do
      assert_equal 1, run_smoke
      assert_equal 'upstream_timeout', JSON.parse(@err.string)['code']
      refute_includes @err.string, 'SECRET'
    end
  end
end
