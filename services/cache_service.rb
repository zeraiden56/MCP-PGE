# frozen_string_literal: true
module Services
  class CacheService
    def initialize(ttl:, clock: -> { Time.now.utc })
      @ttl, @clock = ttl, clock
    end
    def fresh?(processos)
      return false if processos.empty? || @ttl <= 0
      now = @clock.call
      processos.all? do |processo|
        age = now - Time.iso8601(processo.fetch('fonte').fetch('consultado_em'))
        age >= 0 && age < @ttl
      end
    rescue KeyError, ArgumentError, TypeError
      false
    end
  end
end
