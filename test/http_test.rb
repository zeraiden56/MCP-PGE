# frozen_string_literal: true
require_relative 'test_helper'
class HTTPTest < Minitest::Test
  URL = Tribunais::Datajud::Client::ENDPOINTS['TRF1']
  def response(status = 200, body = '{}', headers = {})
    Juridico::HttpClient::Response.new(status: status, body: body, headers: headers)
  end
  def build(*responses, env: {})
    @time, @waits, @calls = 0.0, [], []
    config = Juridico::Config.new({ 'DATAJUD_API_KEY' => 'synthetic-test-token' }.merge(env))
    transport = lambda do |*args|
      @calls << args
      value = responses.shift
      raise value if value.is_a?(Exception)
      value || raise('Mock esgotado')
    end
    Juridico::HttpClient.new(config: config, telemetry: telemetry, transport: transport,
      sleeper: ->(n) { @waits << n; @time += n }, clock: -> { @time }, random: Random.new(1))
  end
  def fetch(client) = client.post(url: URL, body: {}, tribunal: 'TRF1')
  def test_success_and_headers
    assert_equal [{}, 200], fetch(build(response))
    assert_equal 'APIKey synthetic-test-token', @calls[0][2]['Authorization']
    assert_match(/MCP-Juridico/, @calls[0][2]['User-Agent'])
  end
  def test_429_respects_retry_after
    fetch(build(response(429, '{}', 'retry-after' => '7'), response))
    assert_equal [7.0], @waits
  end
  def test_long_retry_after_defers_future_calls
    client = build(response(429, '{}', 'retry-after' => '3600'), response)
    error_code('upstream_http_error') { fetch(client) }
    error_code('rate_limited') { fetch(client) }
    assert_equal 1, @calls.size
    assert_empty @waits
  end
  def test_retry_after_http_date
    date = (Time.now + 10).httpdate
    fetch(build(response(503, '{}', 'retry-after' => date), response))
    assert_operator @waits.first, :>=, 8
  end
  def test_5xx_exponential_backoff_and_limit
    client = build(response(503), response(503), response(503))
    error_code('upstream_http_error') { fetch(client) }
    assert_equal 3, @calls.size
    assert_operator @waits[1], :>, @waits[0]
  end
  def test_timeout_retries_are_bounded
    client = build(Net::ReadTimeout.new, Net::OpenTimeout.new, Net::ReadTimeout.new)
    error_code('upstream_timeout') { fetch(client) }
    assert_equal 3, @calls.size
  end
  def test_auth_and_other_4xx_are_not_retried
    [400, 401, 403, 404, 302].each do |status|
      error_code('upstream_http_error') { fetch(build(response(status))) }
      assert_equal 1, @calls.size
    end
  end
  def test_invalid_json_and_wrong_shape
    ['<html>captcha</html>', '[]', 'null'].each do |body|
      error_code('invalid_response') { fetch(build(response(200, body))) }
      assert_equal 1, @calls.size
    end
  end
  def test_missing_key
    error_code('missing_credentials') { fetch(build(response, env: { 'DATAJUD_API_KEY' => '' })) }
    assert_empty @calls
  end
  def test_rate_limit_applies_to_successive_requests
    client = build(response, response)
    2.times { fetch(client) }
    assert_equal [1.0], @waits
  end
  def test_invalid_config
    %w[-1 NaN Infinity].each do |value|
      error_code('configuration_error') { Juridico::Config.new('HTTP_READ_TIMEOUT_SECONDS' => value) }
    end
  end
end
