# frozen_string_literal: true
module Juridico
  def self.server(service:)
    MCP::Server.new(name: 'mcp-juridico', version: '0.1.0',
      tools: [Tools::BuscarProcesso, Tools::BuscarMovimentacoes, Tools::BuscarDocumentos, Tools::SincronizarProcesso],
      server_context: { service: service })
  end
end
