# frozen_string_literal: true
require 'bundler/setup'
require 'json'
require 'time'
require 'date'
%w[infrastructure/errors infrastructure/config infrastructure/telemetry infrastructure/http_client
   tribunais/cnj tribunais/base_client tribunais/resolver schemas/base schemas/parte schemas/movimentacao
   schemas/documento schemas/processo tribunais/datajud/mapper tribunais/datajud/client
   tribunais/trf1/mapper tribunais/trf1/client tribunais/tjmt/mapper tribunais/tjmt/client
   tribunais/stj/mapper tribunais/stj/client tribunais/stf/mapper tribunais/stf/client
   repositories/processo_repository services/cache_service services/processo_sync
   mcp/tools/base mcp/tools/buscar_processo mcp/tools/buscar_movimentacoes
   mcp/tools/buscar_documentos mcp/tools/sincronizar_processo mcp/server].each { |file| require_relative file }
module Juridico
  def self.build(config: Config.new)
    service, repo = build_service(config: config)
    [server(service: service), repo]
  end

  def self.build_service(config: Config.new)
    unless config.database_url && !config.database_url.empty?
      raise Error.new('configuration_error', 'Configure DATABASE_URL.')
    end
    telemetry = Telemetry.new(metrics_path: config.metrics_path)
    http = HttpClient.new(config: config, telemetry: telemetry)
    clients = { 'TRF1' => Tribunais::TRF1::Client.new(http: http, telemetry: telemetry), 'TJMT' => Tribunais::TJMT::Client.new(http: http, telemetry: telemetry),
                'STJ' => Tribunais::STJ::Client.new(http: http, telemetry: telemetry), 'STF' => Tribunais::STF::Client.new }
    repo = Repositories::ProcessoRepository.new(database_url: config.database_url, store_raw: config.store_raw)
    service = Services::ProcessoSync.new(resolver: Tribunais::TribunalResolver.new(clients), repository: repo,
      cache: Services::CacheService.new(ttl: config.ttl), telemetry: telemetry)
    [service, repo]
  end
end
