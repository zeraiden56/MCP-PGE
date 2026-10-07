# frozen_string_literal: true
require 'net/http'
require 'json'
require 'time'
module Juridico
  class HttpClient
    Response = Struct.new(:status, :body, :headers, keyword_init: true)
    MAX_BYTES = 10 * 1024 * 1024
    TRANSIENT = [Timeout::Error, EOFError, IOError, SocketError, Errno::ECONNRESET,
                 Errno::ECONNREFUSED, Errno::ETIMEDOUT].freeze
    def initialize(config:, telemetry:, transport: nil, sleeper: ->(n) { sleep(n) },
                   clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }, random: Random.new)
      @config, @telemetry, @transport = config, telemetry, transport || method(:perform)
      @sleep, @clock, @random = sleeper, clock, random
      @mutex, @next_request = Mutex.new, 0
    end

    def post(url:, body:, tribunal:)
      raise Error.new('missing_credentials', 'Configure DATAJUD_API_KEY.') if @config.api_key.empty?
      attempts = 0
      loop do
        started, status, attempted, succeeded = @clock.call, nil, false, false
        begin
          throttle!
          started, attempted = @clock.call, true
          response = @transport.call(URI(url), body, {
            'Authorization' => "APIKey #{@config.api_key}",
            'Content-Type' => 'application/json', 'Accept' => 'application/json',
            'User-Agent' => @config.user_agent
          })
          status = response.status.to_i
          raise Error.new('invalid_response', 'Resposta excede limite local.', http_status: status) if response.body.bytesize > MAX_BYTES
          if status == 429 || (500..599).cover?(status)
            delay = [retry_after(response.headers['retry-after']), 2**attempts + @random.rand * 0.25].max
            defer!(delay)
            raise Error.new('upstream_http_error', 'Fonte temporariamente indisponível ou limitada.', http_status: status) if attempts >= @config.retries || delay > @config.max_wait
            attempts += 1
            next
          end
          raise Error.new('upstream_http_error', 'Fonte recusou a consulta.', http_status: status) unless status == 200
          begin
            parsed = JSON.parse(response.body)
          rescue JSON::ParserError
            raise Error.new('invalid_response', 'Fonte retornou JSON inválido.', http_status: status)
          end
          raise Error.new('invalid_response', 'Resposta JSON deve ser objeto.', http_status: status) unless parsed.is_a?(Hash)
          succeeded = true
          return [parsed, status]
        rescue *TRANSIENT
          if attempts >= @config.retries
            raise Error.new('upstream_timeout', 'Falha de conexão ou timeout da fonte.')
          end
          delay = 2**attempts + @random.rand * 0.25
          raise Error.new('upstream_timeout', 'Tempo de retry excede limite local.') if delay > @config.max_wait
          defer!(delay)
          attempts += 1
        rescue OpenSSL::SSL::SSLError
          raise Error.new('upstream_tls_error', 'Não foi possível validar conexão TLS da fonte.')
        ensure
          duration = @clock.call - started
          if attempted
            @telemetry.increment('tribunal_requests_total', { tribunal: tribunal })
            @telemetry.increment('tribunal_request_duration_count', { tribunal: tribunal })
            @telemetry.increment('tribunal_request_duration_sum', { tribunal: tribunal }, duration)
            @telemetry.increment('tribunal_errors_total', { tribunal: tribunal }) unless succeeded
            @telemetry.record('http', tribunal: tribunal, duracao: duration, http_status: status,
                              status: succeeded ? 'ok' : 'error')
          end
        end
      end
    end

    private

    def throttle!
      @mutex.synchronize do
        delay = [@next_request - @clock.call, 0].max
        raise Error.new('rate_limited', 'Fonte em período de espera; tente novamente mais tarde.', http_status: 429) if delay > @config.max_wait
        @sleep.call(delay) if delay.positive?
        @next_request = @clock.call + @config.interval
      end
    end
    def defer!(seconds)
      @mutex.synchronize { @next_request = [@next_request, @clock.call + seconds].max }
    end
    def retry_after(value)
      return 0 unless value
      return value.to_i if value.match?(/\A[0-9]+\z/)
      [Time.httpdate(value) - Time.now, 0].max
    rescue ArgumentError
      0
    end
    def perform(uri, body, headers)
      unless uri.scheme == 'https' && uri.host == 'api-publica.datajud.cnj.jus.br' && uri.port == 443
        raise Error.new('invalid_endpoint', 'Endpoint fora da lista oficial permitida.')
      end
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = @config.open_timeout
      http.read_timeout = @config.read_timeout
      http.write_timeout = @config.read_timeout
      http.max_retries = 0
      request = Net::HTTP::Post.new(uri.request_uri, headers)
      request.body = JSON.generate(body)
      result = nil
      http.request(request) do |response|
        bytes = +''
        response.read_body do |chunk|
          bytes << chunk
          raise Error.new('invalid_response', 'Resposta excede limite local.', http_status: response.code.to_i) if bytes.bytesize > MAX_BYTES
        end
        result = Response.new(status: response.code.to_i, body: bytes, headers: response.each_header.to_h)
      end
      result
    end
  end
end
