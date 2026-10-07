# frozen_string_literal: true
module Juridico
  class Config
    attr_reader :ttl, :open_timeout, :read_timeout, :retries, :interval, :max_wait,
                :user_agent, :api_key, :database_url, :store_raw, :metrics_path
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
    rescue ArgumentError, TypeError
      raise Error.new('configuration_error', 'Configuração de ambiente inválida.')
    end

    private

    def number(env, key, default, minimum)
      value = Float(env.fetch(key, default))
      raise ArgumentError unless value.finite? && value >= minimum
      value
    end
  end
end
