# frozen_string_literal: true
require 'json'
require 'thread'
module Juridico
  class Telemetry
    ALLOWED = %i[tribunal ferramenta duracao status cache http_status].freeze
    def initialize(io: $stderr, metrics_path: nil)
      @io, @path, @metrics, @mutex = io, metrics_path, Hash.new(0), Mutex.new
    end
    def record(event, **fields)
      safe = fields.select { |key, _| ALLOWED.include?(key) }
      @mutex.synchronize { @io.puts(JSON.generate({ evento: event }.merge(safe))) }
    end
    def increment(name, labels = {}, amount = 1)
      permitted = %w[mcp_requests_total tribunal_requests_total tribunal_request_duration_sum tribunal_request_duration_count tribunal_errors_total cache_hits_total]
      return unless permitted.include?(name)
      labels = labels.select { |key, _| %i[tribunal ferramenta status].include?(key) }
      suffix = labels.empty? ? '' : '{' + labels.sort.map { |k, v| "#{k}=#{JSON.generate(v.to_s)}" }.join(',') + '}'
      @mutex.synchronize { @metrics[name + suffix] += amount }
    end
    def export
      @mutex.synchronize { @metrics.sort.map { |key, value| "#{key} #{value}\n" }.join }
    end
    def flush
      return if @path.nil? || @path.empty?
      temp = "#{@path}.#{Process.pid}.tmp"
      File.write(temp, export, mode: 'w', perm: 0o600)
      File.rename(temp, @path)
    rescue SystemCallError
      record('metrics', status: 'write_error')
    end
  end
end
