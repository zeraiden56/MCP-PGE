# frozen_string_literal: true
require_relative 'endpoints'
module Tribunais
  module Datajud
    class Client < BaseClient
      ENDPOINTS = Datajud::ENDPOINTS
      PAGE_SIZE = 100
      MAX_PAGES = 10
      def initialize(tribunal:, http:, mapper: Mapper.new, clock: -> { Time.now.utc }, telemetry: Juridico::Telemetry.new)
        @tribunal, @http, @mapper, @clock = tribunal, http, mapper, clock
        @telemetry = telemetry
        @url = ENDPOINTS.fetch(tribunal)
      end
      def capabilities
        { 'status' => 'supported', 'processo' => true, 'movimentacoes' => true,
          'partes' => false, 'documentos' => false, 'fonte' => 'datajud' }
      end
      def buscar_processo(numero_cnj:)
        cnj = CNJ.new(numero_cnj)
        consulted_at = @clock.call
        pages, hits = [], []
        total = nil
        MAX_PAGES.times do |page|
          body = { 'size' => PAGE_SIZE, 'from' => page * PAGE_SIZE, 'track_total_hits' => true,
                   'query' => { 'bool' => { 'must' => [{ 'match' => { 'numeroProcesso' => cnj.normalizado } }],
                     'filter' => [{ 'term' => { 'nivelSigilo' => 0 } }] } },
                   'sort' => [{ 'id.keyword' => 'asc' }] }
          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          data, status = @http.post(url: @url, body: body, tribunal: @tribunal)
          duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
          current, count = validate_page(data, http_status: status, duration: duration)
          total ||= count
          raise Juridico::Error.new('incomplete_response', 'Índice mudou durante a consulta; sincronize novamente.') if count != total
          pages << data
          hits.concat(current)
          break if hits.size >= total
          raise Juridico::Error.new('incomplete_response', 'Paginação incompleta da fonte.') if current.empty?
        end
        raise Juridico::Error.new('incomplete_response', 'Limite local de resultados excedido.') unless hits.size == total
        if hits.empty?
          raise Juridico::Error.new('not_found', 'Nenhum registro público encontrado nesta fonte; isso não comprova inexistência.', http_status: 200)
        end
        ids = hits.map { |h| h.fetch('_id') }
        raise Juridico::Error.new('incomplete_response', 'Registros repetidos durante paginação.') unless ids.uniq.size == hits.size
        processes = hits.map { |h| @mapper.map(h, cnj: cnj, tribunal: @tribunal, url: @url, consulted_at: consulted_at) }
        unless processes.map { |p| p['id_origem'] }.uniq.size == processes.size
          raise Juridico::Error.new('invalid_response', 'Identificadores canônicos duplicados na fonte.', http_status: 200)
        end
        FetchResult.new(processos: processes, raw: pages, http_status: 200)
      rescue KeyError, TypeError, NoMethodError
        raise Juridico::Error.new('invalid_response', 'Estrutura da resposta DataJud inválida.', http_status: 200)
      end
      def buscar_movimentacoes(numero_cnj:)
        buscar_processo(numero_cnj: numero_cnj).processos.map do |p|
          p.slice('numero_cnj', 'id_origem', 'tribunal', 'grau', 'fonte', 'movimentacoes')
        end
      end
      def buscar_documentos(numero_cnj:)
        raise Juridico::Error.new('unsupported_capability', 'DataJud público não disponibiliza documentos processuais.')
      end

      private

      def validate_page(data, http_status:, duration:)
        shards = data.fetch('_shards')
        failed = shards.fetch('failed')
        unless failed.is_a?(Integer) && failed >= 0
          raise Juridico::Error.new('invalid_response', 'Contagem de shards inválida.', http_status: http_status)
        end
        if failed.positive?
          # Não registrar failures/reason, hits ou qualquer conteúdo livre da fonte.
          counts = %w[total successful failed].to_h do |key|
            value = shards[key]
            ["shards_#{key}".to_sym, value.is_a?(Integer) && value >= 0 ? value : nil]
          end
          @telemetry.record('datajud_partial_response', tribunal: @tribunal,
                            http_status: http_status, duracao: duration, **counts)
          @telemetry.increment('tribunal_errors_total', { tribunal: @tribunal })
          raise Juridico::Error.new('incomplete_response',
            'A fonte respondeu parcialmente e não foi possível validar o resultado.', http_status: http_status)
        end
        unless data.fetch('timed_out') == false
          raise Juridico::Error.new('incomplete_response', 'Fonte retornou resultado parcial.', http_status: 200)
        end
        result = data.fetch('hits')
        total = result.fetch('total')
        unless total.is_a?(Hash) && total['relation'] == 'eq' && total['value'].is_a?(Integer) && total['value'] >= 0 && result['hits'].is_a?(Array)
          raise Juridico::Error.new('invalid_response', 'Total de resultados ausente ou inexato.', http_status: 200)
        end
        [result['hits'], total['value']]
      end
    end
  end
end
