# frozen_string_literal: true
require_relative 'test_helper'
require 'minitest/mock'
load File.expand_path('../bin/health_datajud', __dir__)

class HealthDatajudTest < Minitest::Test
  def response(failed = 0, status: 200)
    Juridico::HttpClient::Response.new(status: status, body: JSON.generate('_shards' => { 'total' => 3, 'failed' => failed },
      'private' => 'SECRET_PAYLOAD'), headers: {})
  end

  def run_health(responses, env = {})
    @out, @err, @calls = StringIO.new, StringIO.new, []
    original = Juridico::HttpClient.method(:new)
    factory = lambda do |config:, telemetry:|
      assert_equal 0, config.retries
      original.call(config: config, telemetry: telemetry, transport: lambda do |uri, body, headers|
        @calls << [uri, body]
        value = responses.shift
        raise value if value.is_a?(Exception)
        value
      end, sleeper: ->(_) {})
    end
    Juridico.stub(:build_service, ->(**) { flunk 'Não pode construir serviço/banco' }) do
      Juridico::HttpClient.stub(:new, factory) do
        Juridico::HealthDatajud.run(env: { 'DATAJUD_API_KEY' => 'SECRET_KEY', 'HTTP_MAX_RETRIES' => '3' }.merge(env), out: @out, err: @err)
      end
    end
  end

  def test_healthy_degraded_down_and_minimal_query
    assert_equal 1, run_health([response, response(1), response(status: 503)])
    assert_includes @out.string, 'TRF1 | healthy | 200 | 3 | 0'
    assert_includes @out.string, 'TJMT | degraded | 200 | 3 | 1'
    assert_includes @out.string, 'STJ | down | 503'
    assert_equal 3, @calls.size
    @calls.each do |_uri, body|
      assert_equal 0, body['size']
      assert_equal false, body['track_total_hits']
    end
    %w[SECRET_KEY SECRET_PAYLOAD].each { |secret| refute_includes @out.string + @err.string, secret }
  end

  def test_all_healthy_exit_zero
    assert_equal 0, run_health([response, response, response])
  end

  def test_http_errors_and_connection_failures_are_down_without_retries
    [429, 502, 503, 504].each do |status|
      assert_equal 1, run_health([response(status: status), response, response])
      assert_includes @out.string, "TRF1 | down | #{status}"
      assert_equal 3, @calls.size
    end
    [Net::ReadTimeout.new('SECRET'), SocketError.new('SECRET'), Errno::ECONNREFUSED.new].each do |failure|
      assert_equal 1, run_health([failure, response, response])
      assert_includes @out.string, 'TRF1 | down | -'
      assert_equal 3, @calls.size
      refute_includes @err.string, 'SECRET'
    end
  end

  def test_malformed_and_auth_errors_are_not_healthy
    bad = Juridico::HttpClient::Response.new(status: 200, body: '{}', headers: {})
    assert_equal 1, run_health([bad, response(status: 401), response])
    assert_includes @out.string, 'TRF1 | error | 200'
    assert_includes @out.string, 'TJMT | error | 401'
  end

  def test_deadline_and_no_retry
    http = Object.new
    calls = 0
    http.define_singleton_method(:post) do |**|
      calls += 1
      sleep 0.05
    end
    @out, @err = StringIO.new, StringIO.new
    Juridico::HttpClient.stub(:new, http) do
      assert_equal 1, Juridico::HealthDatajud.run(env: { 'DATAJUD_API_KEY' => 'SECRET',
        'HEALTH_DATAJUD_TIMEOUT_SECONDS' => '0.01' }, out: @out, err: @err)
    end
    assert_equal 3, calls
    assert_equal 3, @out.string.scan('down').size
  end

  def test_invalid_configuration_makes_no_requests
    assert_equal 2, run_health([], 'HEALTH_DATAJUD_TIMEOUT_SECONDS' => 'NaN')
    assert_empty @calls
    assert_empty @out.string
  end
end
