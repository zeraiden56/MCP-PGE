# frozen_string_literal: true
require 'mcp'
module Juridico
  module Tools
    class Base < MCP::Tool
      def self.call(numero_cnj:, server_context:)
        result = server_context[:service].call(ferramenta: name_value, numero_cnj: numero_cnj)
        MCP::Tool::Response.new([{ type: 'text', text: JSON.generate(result) }], structured_content: result)
      rescue Juridico::Error => error
        result = { 'status' => 'error', 'code' => error.code, 'message' => error.message, 'http_status' => error.http_status }
        MCP::Tool::Response.new([{ type: 'text', text: JSON.generate(result) }], error: true, structured_content: result)
      rescue StandardError
        # Exceções de bibliotecas podem carregar SQL, URL de conexão ou headers.
        result = { 'status' => 'error', 'code' => 'internal_error', 'message' => 'Falha interna ao executar consulta.' }
        MCP::Tool::Response.new([{ type: 'text', text: JSON.generate(result) }], error: true, structured_content: result)
      end
      def self.configure(name:, description:)
        tool_name name
        self.description description
        input_schema(type: 'object', properties: { numero_cnj: { type: 'string', minLength: 20, maxLength: 25,
          description: 'Número CNJ completo, com pontuação padrão ou 20 dígitos.' } },
          required: ['numero_cnj'], additionalProperties: false)
      end
    end
  end
end
