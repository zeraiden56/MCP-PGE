# frozen_string_literal: true

require_relative 'test_helper'
load File.expand_path('../bin/health_datajud', __dir__)

class HealthDatajudTest < Minitest::Test
  def run_health(responses:, env: {})
    @out = StringIO.new
    @err = StringIO.new
    @http = FakeHTTP.new(*responses)

    base_env = {
      'DATAJUD_API_KEY' => 'test-key',
      'HEALTH_DATAJUD_TIMEOUT_SECONDS' => '30'
    }

    result = nil

    Juridico::HttpClient.stub(:new, @http) do
      result =
        Juridico::HealthDatajud.run(
          env: base_env.merge(env),
          out: @out,
          err: @err
        )
    end

    result
  end

  def rows
    lines = @out.string.lines

    headers =
      lines
        .first
        .strip
        .split(/\s*\|\s*/)
        .map(&:to_sym)

    lines
      .drop(2)
      .to_h do |line|
        values =
          line
            .strip
            .split(/\s*\|\s*/)

        row =
          headers
            .zip(values)
            .to_h

        [
          row[:tribunal],
          row
        ]
      end
  end

  def shard_response(total: 3, failed: 0)
    {
      '_shards' => {
        'total' => total,
        'successful' => total - failed,
        'skipped' => 0,
        'failed' => failed
      }
    }
  end

  def test_healthy_degraded_down_and_minimal_query
    failure =
      Juridico::Error.new(
        'upstream_http_error',
        'service unavailable',
        http_status: 503
      )

    assert_equal(
      1,
      run_health(
        responses: [
          shard_response(total: 3, failed: 0),
          shard_response(total: 3, failed: 1),
          failure
        ]
      )
    )

    assert_equal 'healthy', rows['TRF1'][:status]
    assert_equal '200', rows['TRF1'][:http_status]
    assert_equal '3', rows['TRF1'][:shards_total]
    assert_equal '0', rows['TRF1'][:shards_failed]

    assert_equal 'degraded', rows['TJMT'][:status]
    assert_equal '200', rows['TJMT'][:http_status]
    assert_equal '3', rows['TJMT'][:shards_total]
    assert_equal '1', rows['TJMT'][:shards_failed]

    assert_equal 'down', rows['STJ'][:status]
    assert_equal '503', rows['STJ'][:http_status]

    assert_equal 'unsupported', rows['STF'][:status]
    assert_equal '-', rows['STF'][:http_status]

    assert_equal 3, @http.calls.size

    @http.calls.each do |call|
      body = call.fetch(:body)

      assert_equal 0, body['size']
      assert_equal false, body['track_total_hits']
      assert_equal(
        { 'match_all' => {} },
        body['query']
      )
    end
  end

  def test_http_errors_and_connection_failures_are_down_without_retries
    rate_limited =
      Juridico::Error.new(
        'rate_limited',
        'too many requests',
        http_status: 429
      )

    assert_equal(
      1,
      run_health(
        responses: [
          rate_limited,
          shard_response,
          shard_response
        ]
      )
    )

    assert_equal 'down', rows['TRF1'][:status]
    assert_equal '429', rows['TRF1'][:http_status]

    assert_equal 'healthy', rows['TJMT'][:status]
    assert_equal '200', rows['TJMT'][:http_status]

    assert_equal 'healthy', rows['STJ'][:status]
    assert_equal '200', rows['STJ'][:http_status]

    assert_equal 'unsupported', rows['STF'][:status]

    assert_equal 3, @http.calls.size
  end

  def test_malformed_and_auth_errors_are_not_healthy
    malformed = {
      'not_shards' => {}
    }

    unauthorized =
      Juridico::Error.new(
        'upstream_http_error',
        'unauthorized',
        http_status: 401
      )

    assert_equal(
      1,
      run_health(
        responses: [
          malformed,
          unauthorized,
          shard_response
        ]
      )
    )

    assert_equal 'error', rows['TRF1'][:status]
    assert_equal '200', rows['TRF1'][:http_status]

    assert_equal 'down', rows['TJMT'][:status]
    assert_equal '401', rows['TJMT'][:http_status]

    assert_equal 'healthy', rows['STJ'][:status]
    assert_equal '200', rows['STJ'][:http_status]

    assert_equal 'unsupported', rows['STF'][:status]
  end

  def test_invalid_configuration_returns_2
    @out = StringIO.new
    @err = StringIO.new

    assert_equal(
      2,
      Juridico::HealthDatajud.run(
        env: {
          'DATAJUD_API_KEY' => '',
          'HEALTH_DATAJUD_TIMEOUT_SECONDS' => '30'
        },
        out: @out,
        err: @err
      )
    )

    assert_includes(
      @err.string,
      'Configuração inválida'
    )
  end

  def test_invalid_timeout_returns_2
    @out = StringIO.new
    @err = StringIO.new

    assert_equal(
      2,
      Juridico::HealthDatajud.run(
        env: {
          'DATAJUD_API_KEY' => 'test-key',
          'HEALTH_DATAJUD_TIMEOUT_SECONDS' => '0'
        },
        out: @out,
        err: @err
      )
    )
  end
end