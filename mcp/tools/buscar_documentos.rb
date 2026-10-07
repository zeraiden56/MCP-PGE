# frozen_string_literal: true
module Juridico
  module Tools
    class BuscarDocumentos < Base
      configure name: 'buscar_documentos', description: 'Consulta metadados de documentos quando a fonte permitir. Atualmente DataJud não oferece esta capacidade; retorna unsupported_capability sem download.'
    end
  end
end
