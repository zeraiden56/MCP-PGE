# frozen_string_literal: true
module Juridico
  module Tools
    class SincronizarProcesso < Base
      configure name: 'sincronizar_processo', description: 'Força consulta à fonte oficial e atualiza o cache PostgreSQL. Retorna capas públicas e consultado_em; não altera o processo no tribunal.'
    end
  end
end
