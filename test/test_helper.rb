# frozen_string_literal: true
require 'minitest/autorun'
require 'stringio'
require_relative '../boot'
# Nenhum teste unitário pode acessar a rede, mesmo por acidente.
Net::HTTP.singleton_class.prepend(Module.new do
  def new(*) = raise('Rede desativada nos testes; use transporte falso.')
end)
module TestData
  NOW = Time.utc(2026, 10, 7, 12)
  def cnj(segment = '4', region = '01', origin = '3202', sequence = '0000001')
    base = "#{sequence}2026#{segment}#{region}#{origin}"
    dd = format('%02d', 98 - "#{base}00".to_i % 97)
    "#{sequence}#{dd}2026#{segment}#{region}#{origin}"
  end
  def fixture(tribunal = 'TRF1')
    JSON.parse(File.read(File.join(__dir__, 'fixtures', "#{tribunal.downcase}.json")))
  end
  def telemetry = Juridico::Telemetry.new(io: StringIO.new)
  def canonical(tribunal = 'TRF1')
    hit = fixture(tribunal)['hits']['hits'].first
    Tribunais.const_get(tribunal)::Mapper.new.map(hit, cnj: Tribunais::CNJ.new(hit['_source']['numeroProcesso']),
      tribunal: tribunal, url: Tribunais::Datajud::Client::ENDPOINTS[tribunal], consulted_at: NOW)
  end
  def error_code(code)
    error = assert_raises(Juridico::Error) { yield }
    assert_equal code, error.code
    error
  end
  class FakeHTTP
    attr_reader :calls
    def initialize(*responses)
      @responses, @calls = responses, []
    end
    def post(**args)
      @calls << args
      value = @responses.shift
      raise value if value.is_a?(Exception)
      raise 'Resposta mock não configurada' unless value
      [value, 200]
    end
  end
  class MemoryRepository
    attr_reader :data, :audits
    def initialize
      @data, @audits = [], []
    end
    def with_lock(*) = yield
    def find(**) = Marshal.load(Marshal.dump(@data))
    def start_sync(**args)
      @audits << args.merge(status: 'running')
      @audits.size - 1
    end
    def save(result, sync_id:)
      @data = result.processos
      @audits[ sync_id ][:status] = 'success'
      @data
    end
    def fail_sync(id, error) = @audits[id].merge!(status: 'error', error: error.code)
    def invalidate(**) = @data.clear
  end
end
class Minitest::Test
  include TestData
end
