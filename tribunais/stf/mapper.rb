# frozen_string_literal: true
module Tribunais
  module STF
    # Sem contrato de resposta confirmado: nenhuma transformação fictícia.
    class Mapper
      def map(*)
        raise Juridico::Error.new('unsupported_tribunal', 'Não foi possível confirmar uma API pública oficial adequada.')
      end
    end
  end
end
