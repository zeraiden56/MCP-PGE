# frozen_string_literal: true
module Tribunais
  FetchResult = Struct.new(:processos, :raw, :http_status, keyword_init: true)
  class BaseClient
    def buscar_processo(numero_cnj:) = raise(NotImplementedError)
    def buscar_movimentacoes(numero_cnj:) = raise(NotImplementedError)
    def buscar_documentos(numero_cnj:) = raise(NotImplementedError)
    def capabilities = raise(NotImplementedError)
  end
end
