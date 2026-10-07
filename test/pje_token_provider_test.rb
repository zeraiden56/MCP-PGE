# frozen_string_literal: true
require_relative 'test_helper'
class PjeTokenProviderTest < Minitest::Test
  SECRET = 'synthetic-secret+&='
  TOKEN = 'synthetic-access-token'
  URL = 'https://sso.example.invalid/approved-token'
  def response(status = 200, data = { 'access_token' => TOKEN, 'expires_in' => 300, 'token_type' => 'Bearer' }, type = 'application/json')
    Juridico::HttpClient::Response.new(status: status,
      body: data.is_a?(String) ? data : JSON.generate(data), headers: { 'content-type' => type })
  end
  def build(*responses, env: {})
    @time, @calls = 0.0, []
    @config = Juridico::Config.new({ 'PJE_ENABLED' => 'true', 'PJE_SSO_URL' => URL,
      'PJE_CLIENT_ID' => 'synthetic-client', 'PJE_CLIENT_SECRET' => SECRET }.merge(env))
    transport = lambda do |*args|
      @calls << args
      item = responses.shift || raise('Fixture esgotada')
      raise item if item.is_a?(Exception)
      item
    end
    Tribunais::Pje::Auth::TokenProvider.new(config: @config, transport: transport, clock: -> { @time })
  end
  def test_obtains_token_with_form_encoded_credentials
    provider = build(response)
    assert_equal TOKEN, provider.access_token
    uri, body, headers = @calls.first
    assert_equal URL, uri.to_s
    assert_equal 'application/x-www-form-urlencoded', headers['Content-Type']
    assert_equal 'application/json', headers['Accept']
    assert_equal({ 'grant_type' => 'client_credentials', 'client_id' => 'synthetic-client',
      'client_secret' => SECRET }, URI.decode_www_form(body).to_h)
    refute headers.key?('Authorization')
    assert_equal 30, @config.pje_token_expiry_margin
  end
  def test_reuses_valid_token
    provider = build(response)
    2.times { assert_equal TOKEN, provider.access_token }
    assert_equal 1, @calls.size
  end
  def test_renews_expired_token
    provider = build(response, response(200, { 'access_token' => 'new-token', 'expires_in' => 300 }))
    provider.access_token
    @time = 301
    assert_equal 'new-token', provider.access_token
    assert_equal 2, @calls.size
  end
  def test_renews_at_safety_margin
    provider = build(response, response)
    provider.access_token
    @time = 269
    provider.access_token
    assert_equal 1, @calls.size
    @time = 270
    provider.access_token
    assert_equal 2, @calls.size
  end
  def test_configurable_safety_margin
    provider = build(response, response, env: { 'PJE_TOKEN_EXPIRY_MARGIN_SECONDS' => '5' })
    provider.access_token
    @time = 294
    provider.access_token
    assert_equal 1, @calls.size
    @time = 295
    provider.access_token
    assert_equal 2, @calls.size
  end
  def test_invalid_expiry_is_safe
    [nil, 0, -1, '300', 'NaN', true, {}, []].each do |expiry|
      provider = build(response(200, { 'access_token' => TOKEN, 'expires_in' => expiry }))
      error = error_code('pje_token_error') { provider.access_token }
      refute_includes error.full_message, TOKEN
      refute_includes error.full_message, SECRET
    end
  end
  def test_missing_or_invalid_access_token
    [nil, '', 123, 'token with spaces', "token\r\n"].each do |token|
      provider = build(response(200, { 'access_token' => token, 'expires_in' => 300 }))
      error_code('pje_token_error') { provider.access_token }
    end
  end
  def test_401_is_authentication_error
    error = error_code('pje_authentication_error') { build(response(401)).access_token }
    assert_equal 401, error.http_status
  end
  def test_403_is_authorization_error
    error = error_code('pje_authorization_error') { build(response(403)).access_token }
    assert_equal 403, error.http_status
  end
  def test_timeout_is_safe
    [Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout].each do |type|
      error = error_code('pje_timeout') { build(type.new(SECRET)).access_token }
      refute_includes error.full_message, SECRET
      assert_nil error.cause
    end
  end
  def test_secret_and_token_never_appear_in_output_or_logs
    provider = build(response, RuntimeError.new("#{SECRET} #{TOKEN}"))
    log = StringIO.new
    logger = Juridico::Telemetry.new(io: log)
    out, err = capture_io do
      assert_equal TOKEN, provider.access_token
      logger.record('objects', provider: provider.inspect, config: @config.inspect)
      @time = 301
      error = error_code('pje_token_error') { provider.access_token }
      warn error.full_message
    end
    [SECRET, TOKEN].each do |value|
      refute_includes out + err + log.string + provider.inspect + @config.inspect, value
    end
  end
  def test_disabled_does_not_attempt_http
    provider = build(response, env: { 'PJE_ENABLED' => 'false' })
    error_code('pje_disabled') { provider.access_token }
    assert_empty @calls
  end
  def test_disabled_is_default
    refute Juridico::Config.new({}).pje_enabled
  end
  def test_missing_configuration_does_not_attempt_http
    %w[PJE_SSO_URL PJE_CLIENT_ID PJE_CLIENT_SECRET].each do |key|
      provider = build(response, env: { key => '' })
      error_code('pje_missing_credentials') { provider.access_token }
      assert_empty @calls
    end
  end
  def test_insecure_or_ambiguous_url_is_rejected_before_http
    ['http://sso.example.invalid/token', 'https://user:pass@sso.example.invalid/token',
     'https://sso.example.invalid:8443/token', 'https://sso.example.invalid/token#fragment',
     'https://sso.example.invalid/token?secret=value', 'not a url'].each do |url|
      provider = build(response, env: { 'PJE_SSO_URL' => url })
      error_code('pje_missing_credentials') { provider.access_token }
      assert_empty @calls
    end
  end
  def test_unexpected_http_status_is_not_retried
    [302, 400, 404, 429, 500].each do |status|
      provider = build(response(status))
      error = error_code('pje_http_error') { provider.access_token }
      assert_equal status, error.http_status
      assert_equal 1, @calls.size
    end
  end
  def test_invalid_json_shape_and_content_type
    ['<html>login</html>', '[]', 'null', '{'].each do |body|
      error_code('pje_token_error') { build(response(200, body)).access_token }
    end
    error_code('pje_token_error') { build(response(200, '{}', 'text/html')).access_token }
  end
  def test_response_size_is_bounded
    error_code('pje_token_error') { build(response(200, 'x' * 65_537)).access_token }
  end
  def test_concurrent_callers_share_one_token
    provider = build(response)
    values = 12.times.map { Thread.new { provider.access_token } }.map(&:value)
    assert_equal [TOKEN], values.uniq
    assert_equal 1, @calls.size
  end
  def test_failed_renewal_never_returns_expired_token
    provider = build(response, response(403), response)
    provider.access_token
    @time = 301
    error_code('pje_authorization_error') { provider.access_token }
    assert_equal TOKEN, provider.access_token
    assert_equal 3, @calls.size
  end
  def test_request_duration_does_not_extend_token_lifetime
    config = Juridico::Config.new('PJE_ENABLED' => 'true', 'PJE_SSO_URL' => URL,
      'PJE_CLIENT_ID' => 'client', 'PJE_CLIENT_SECRET' => SECRET)
    @time = 0
    provider = Tribunais::Pje::Auth::TokenProvider.new(config: config, clock: -> { @time },
      transport: ->(*) { @time = 301; response })
    error_code('pje_token_error') { provider.access_token }
  end
  def test_invalid_margin_rejected
    %w[-1 NaN Infinity].each do |margin|
      error_code('configuration_error') { Juridico::Config.new('PJE_TOKEN_EXPIRY_MARGIN_SECONDS' => margin) }
    end
  end
end
