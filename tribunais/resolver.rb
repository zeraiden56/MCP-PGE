# frozen_string_literal: true
module Tribunais
  class TribunalResolver
    ORIGENS = { ['4', '01'] => 'TRF1', ['8', '11'] => 'TJMT',
                ['3', '00'] => 'STJ', ['1', '00'] => 'STF' }.freeze
    Resolution = Struct.new(:cnj, :tribunal, :client, keyword_init: true)
    def initialize(clients)
      @clients = clients
    end

    def resolve(numero_cnj)
      cnj = CNJ.new(numero_cnj)
      tribunal = ORIGENS[[cnj.segmento, cnj.regiao]]
      client = @clients[tribunal]
      unless client
        raise Juridico::Error.new('unsupported_tribunal', 'Tribunal de origem ainda não suportado.')
      end
      Resolution.new(cnj: cnj, tribunal: tribunal, client: client)
    end
  end
end
