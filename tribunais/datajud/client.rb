# frozen_string_literal: true
module Tribunais
  module Datajud
    class Client < BaseClient
      ENDPOINTS = {
        'TRF1' => 'https://api-publica.datajud.cnj.jus.br/api_publica_trf1/_search',
        'TJMT' => 'https://api-publica.datajud.cnj.jus.br/api_publica_tjmt/_search',
        'STJ' => 'https://api-publica.datajud.cnj.jus.br/api_publica_stj/_search'
      }.freeze
      PAGE_SIZE = 100
      MAX_PAGES = 10
      def initialize(tribunal:, http:, mapper: Mapper.new, clock: -> { Time.now.utc })
        @tribunal, @http, @mapper, @clock = tribunal, http, mapper, clock
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
          data, _status = @http.post(url: @url, body: body, tribunal: @tribunal)
          current, count = validate_page(data)
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

      def validate_page(data)
        unless data.fetch('timed_out') == false && data.fetch('_shards').fetch('failed') == 0
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
