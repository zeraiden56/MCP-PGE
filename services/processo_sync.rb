# frozen_string_literal: true
module Services
  class ProcessoSync
    attr_reader :resolver
    OPERATIONS = { 'buscar_processo' => 'processo', 'buscar_movimentacoes' => 'movimentacoes',
                   'buscar_documentos' => 'documentos', 'sincronizar_processo' => 'processo' }.freeze
    def initialize(resolver:, repository:, cache:, telemetry:)
      @resolver, @repository, @cache, @telemetry = resolver, repository, cache, telemetry
    end
    def call(ferramenta:, numero_cnj:)
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      cache_status, status, tribunal, http_status = 'miss', 'error', nil, nil
      operation = OPERATIONS.fetch(ferramenta)
      resolution = @resolver.resolve(numero_cnj)
      tribunal, client, cnj = resolution.tribunal, resolution.client, resolution.cnj
      capabilities = client.capabilities
      if capabilities['status'] == 'unsupported'
        raise Juridico::Error.new('unsupported_tribunal', 'Não foi possível confirmar uma API pública oficial adequada.')
      end
      unless capabilities[operation]
        raise Juridico::Error.new('unsupported_capability', 'A fonte oficial selecionada não disponibiliza esta capacidade.')
      end
      processes = @repository.with_lock("#{tribunal}:#{cnj.normalizado}") do
        cached = @repository.find(numero: cnj.normalizado, tribunal: tribunal)
        if ferramenta != 'sincronizar_processo' && @cache.fresh?(cached)
          cache_status = 'hit'
          @telemetry.increment('cache_hits_total', { tribunal: tribunal })
          cached
        else
          sync_id = @repository.start_sync(numero: cnj.normalizado, tribunal: tribunal, fonte: capabilities.fetch('fonte'))
          begin
            result = client.buscar_processo(numero_cnj: cnj.normalizado)
            http_status = result.http_status
            @repository.save(result, sync_id: sync_id)
          rescue StandardError => error
            @repository.fail_sync(sync_id, error)
            if error.is_a?(Juridico::Error) && %w[not_found non_public_record].include?(error.code)
              @repository.invalidate(numero: cnj.normalizado, tribunal: tribunal)
            end
            raise
          end
        end
      end
      status = 'ok'
      fields = {
        'buscar_movimentacoes' => %w[numero_cnj tribunal tribunal_origem id_origem grau fonte fonte_consulta movimentacoes],
        'buscar_documentos' => %w[numero_cnj tribunal tribunal_origem id_origem grau fonte fonte_consulta documentos]
      }[ferramenta]
      output = fields ? processes.map { |p| p.slice(*fields) } : processes
      { 'status' => status, 'cache' => cache_status, 'consultado_em' => processes.map { |p| p['fonte']['consultado_em'] }.min,
        'capacidades' => capabilities, 'origem' => { 'tribunal' => tribunal, 'segmento' => cnj.segmento,
          'regiao' => cnj.regiao, 'unidade' => cnj.origem, 'tipo' => cnj.tipo_origem }, 'processos' => output }
    rescue Juridico::Error => e
      http_status = e.http_status
      raise
    ensure
      duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
      @telemetry.increment('mcp_requests_total', { ferramenta: ferramenta, status: status })
      @telemetry.record('tool', tribunal: tribunal, ferramenta: ferramenta, duracao: duration,
                        status: status, cache: cache_status, http_status: http_status)
      @telemetry.flush
    end
  end
end
