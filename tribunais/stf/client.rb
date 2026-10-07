# frozen_string_literal: true
module Tribunais
  module STF
    class Client < BaseClient
      def capabilities
        { 'status' => 'unsupported', 'processo' => false, 'movimentacoes' => false,
          'partes' => false, 'documentos' => false, 'fonte' => nil }
      end
      def buscar_processo(numero_cnj:)
        raise Juridico::Error.new('unsupported_tribunal', 'Não foi possível confirmar uma API pública oficial adequada.')
      end
      alias buscar_movimentacoes buscar_processo
      alias buscar_documentos buscar_processo
    end
  end
end
