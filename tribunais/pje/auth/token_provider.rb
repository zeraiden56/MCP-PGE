# frozen_string_literal: true
require 'net/http'
require 'json'
require 'uri'
require_relative '../../../infrastructure/errors'
require_relative '../../../infrastructure/http_client'
module Tribunais
  module Pje
    module Auth
      class TokenProvider
        MAX_BYTES = 64 * 1024
        def initialize(config:, transport: nil, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
          @config, @clock = config, clock
          @transport = transport || method(:perform_form)
          @mutex = Mutex.new
          @token, @expires_at = nil, 0
        end
        def inspect = '#<Tribunais::Pje::Auth::TokenProvider [REDACTED]>'
        alias to_s inspect
        def access_token
          @mutex.synchronize do
            fail_with('pje_disabled') unless @config.pje_enabled
            uri = configured_uri
            return @token if @token && @clock.call < @expires_at - @config.pje_token_expiry_margin
            started = @clock.call
            response = @transport.call(uri, URI.encode_www_form(
              'grant_type' => 'client_credentials', 'client_id' => @config.pje_client_id,
              'client_secret' => @config.pje_client_secret
            ), { 'Content-Type' => 'application/x-www-form-urlencoded', 'Accept' => 'application/json' })
            status = response.status
            case status
            when 401 then fail_with('pje_authentication_error', status)
            when 403 then fail_with('pje_authorization_error', status)
            when 200 then nil
            else fail_with('pje_http_error', status)
            end
            type = response.headers.find { |key, _| key.to_s.downcase == 'content-type' }&.last.to_s
            unless type.split(';').first.to_s.strip.downcase == 'application/json' &&
                   response.body.is_a?(String) && response.body.bytesize <= MAX_BYTES
              fail_with('pje_token_error')
            end
            data = JSON.parse(response.body)
            unless data.is_a?(Hash) && data['access_token'].is_a?(String) &&
                   data['access_token'].match?(/\A[A-Za-z0-9\-._~+\/=]+\z/) &&
                   data['expires_in'].is_a?(Numeric) && data['expires_in'].finite? && data['expires_in'].positive? &&
                   (!data.key?('token_type') || data['token_type'].to_s.downcase == 'bearer')
              fail_with('pje_token_error')
            end
            expires_at = started + data['expires_in']
            fail_with('pje_token_error') unless expires_at.finite? && @clock.call < expires_at
            @expires_at, @token = expires_at, data['access_token'].dup.freeze
            @token
          end
        rescue Juridico::Error => error
          allowed = %w[pje_disabled pje_missing_credentials pje_authentication_error pje_authorization_error pje_timeout pje_token_error pje_http_error]
          code = allowed.include?(error.code) ? error.code : 'pje_token_error'
          fail_with(code, error.http_status)
        rescue Timeout::Error
          fail_with('pje_timeout')
        rescue StandardError
          fail_with('pje_token_error')
        end
        private
        def fail_with(code, status = nil)
          raise Juridico::Error.new(code, 'Falha segura na autenticação PJe.', http_status: status), cause: nil
        end
        def configured_uri
          if [@config.pje_sso_url, @config.pje_client_id, @config.pje_client_secret].any? { |value| value.to_s.strip.empty? }
            fail_with('pje_missing_credentials')
          end
          uri = URI.parse(@config.pje_sso_url)
          unless uri.is_a?(URI::HTTPS) && uri.host && uri.port == 443 &&
                 uri.userinfo.nil? && uri.query.nil? && uri.fragment.nil? && !uri.path.empty?
            fail_with('pje_missing_credentials')
          end
          uri
        rescue URI::InvalidURIError
          fail_with('pje_missing_credentials')
        end
        # Administrative URL only. Separate from DataJud's JSON/APIKey contract.
        # No retries, redirects, proxy, logging or persistence.
        def perform_form(uri, body, headers)
          http = Net::HTTP.new(uri.host, uri.port, nil)
          http.use_ssl = true
          http.verify_mode = OpenSSL::SSL::VERIFY_PEER
          http.open_timeout = @config.open_timeout
          http.read_timeout = @config.read_timeout
          http.write_timeout = @config.read_timeout
          http.max_retries = 0
          request = Net::HTTP::Post.new(uri.request_uri, headers)
          request.body = body
          result = nil
          http.request(request) do |response|
            bytes = +''
            response.read_body do |chunk|
              bytes << chunk
              fail_with('pje_token_error') if bytes.bytesize > MAX_BYTES
            end
            result = Juridico::HttpClient::Response.new(status: response.code.to_i,
              body: bytes, headers: response.each_header.to_h)
          end
          result
        end
      end
    end
  end
end
