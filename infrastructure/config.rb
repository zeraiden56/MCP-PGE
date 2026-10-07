# frozen_string_literal: true
module Juridico
  class Config
    attr_reader :ttl, :open_timeout, :read_timeout, :retries, :interval, :max_wait,
                :user_agent, :api_key, :database_url, :store_raw, :metrics_path,
                :pje_enabled, :pje_sso_url, :pje_client_id, :pje_client_secret, :pje_api_base_url, :pje_token_expiry_margin
    def initialize(env = ENV)
      @ttl = number(env, 'CACHE_TTL_SECONDS', 3600, 0)
      @open_timeout = number(env, 'HTTP_OPEN_TIMEOUT_SECONDS', 5, 0.01)
      @read_timeout = number(env, 'HTTP_READ_TIMEOUT_SECONDS', 20, 0.01)
      @retries = Integer(env.fetch('HTTP_MAX_RETRIES', '2'))
      raise ArgumentError unless (0..3).cover?(@retries)
      @interval = number(env, 'HTTP_MIN_INTERVAL_SECONDS', 1, 0.01)
      @max_wait = number(env, 'HTTP_MAX_RETRY_WAIT_SECONDS', 30, 0)
      @user_agent = env.fetch('HTTP_USER_AGENT', 'MCP-Juridico/0.1')
      raise ArgumentError if @user_agent.empty? || @user_agent.match?(/[\r\n]/)
      @api_key = env.fetch('DATAJUD_API_KEY', '')
      @database_url = env['DATABASE_URL']
      @store_raw = env.fetch('STORE_RAW_PAYLOAD', 'false') == 'true'
      @metrics_path = env['METRICS_PATH']
      @pje_enabled = env.fetch('PJE_ENABLED', 'false') == 'true'
      @pje_sso_url = env.fetch('PJE_SSO_URL', '').dup.freeze
      @pje_client_id = env.fetch('PJE_CLIENT_ID', '').dup.freeze
      @pje_client_secret = env.fetch('PJE_CLIENT_SECRET', '').dup.freeze
      @pje_api_base_url = env.fetch('PJE_API_BASE_URL', '').dup.freeze
      @pje_token_expiry_margin = number(env, 'PJE_TOKEN_EXPIRY_MARGIN_SECONDS', 30, 0)
    rescue ArgumentError, TypeError
      raise Error.new('configuration_error', 'Configuração de ambiente inválida.')
    end

    def inspect = '#<Juridico::Config [REDACTED]>'
    alias to_s inspect

    private

    def number(env, key, default, minimum)
      value = Float(env.fetch(key, default))
      raise ArgumentError unless value.finite? && value >= minimum
      value
    end
  end
end
