# frozen_string_literal: true
module Juridico
  module Tools
    class BuscarProcesso < Base
      configure name: 'buscar_processo', description: 'Consulta capas públicas no tribunal de origem; retorna todas as capas e consultado_em. Não descobre recursos em outros tribunais. Partes e documentos dependem das capacidades da fonte.'
    end
  end
end
