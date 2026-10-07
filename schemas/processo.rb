# frozen_string_literal: true
module Schemas
  class Processo < Base
    FIELDS = %i[numero_cnj tribunal tribunal_origem grau classe assuntos orgao_julgador
                data_ajuizamento situacao partes movimentacoes documentos fonte fonte_consulta id_origem].freeze
    def validate!
      %i[numero_cnj tribunal tribunal_origem id_origem fonte_consulta].each { |k| required_string!(k) }
      Tribunais::CNJ.new(@values[:numero_cnj])
      %i[assuntos partes movimentacoes documentos].each do |k|
        raise ArgumentError unless @values[k].is_a?(Array)
      end
      fonte = @values[:fonte]
      raise ArgumentError unless fonte.is_a?(Hash)
      Time.iso8601(fonte.fetch('consultado_em'))
    end
  end
end
