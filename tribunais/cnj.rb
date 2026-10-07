# frozen_string_literal: true
module Tribunais
  class CNJ
    FORMATTED = /\A[0-9]{7}-[0-9]{2}\.[0-9]{4}\.[1-9]\.[0-9]{2}\.[0-9]{4}\z/
    COMPACT = /\A[0-9]{20}\z/
    REGIONS = { '1' => [0], '2' => [0], '3' => [0], '4' => [*(1..6), 90],
                '5' => [*(0..24), 90], '6' => (0..27).to_a,
                '7' => (0..12).to_a, '8' => (1..27).to_a, '9' => [13, 21, 26] }.freeze
    attr_reader :normalizado, :sequencial, :digito, :ano, :segmento, :regiao, :origem
    def initialize(value)
      invalid! unless value.is_a?(String) && (FORMATTED.match?(value) || COMPACT.match?(value))
      @normalizado = value.delete('-.')
      @sequencial, @digito, @ano, @segmento, @regiao, @origem =
        @normalizado.match(/\A(.{7})(.{2})(.{4})(.)(.{2})(.{4})\z/).captures
      invalid! unless REGIONS.fetch(segmento, []).include?(regiao.to_i)
      invalid! if ano.to_i.zero? || sequencial.to_i.zero?
      invalid! unless digito.to_i == 98 - "#{sequencial}#{ano}#{segmento}#{regiao}#{origem}00".to_i % 97
      invalid! if %w[1 2 3].include?(segmento) && origem != '0000'
      freeze
    end

    def formatado = "#{sequencial}-#{digito}.#{ano}.#{segmento}.#{regiao}.#{origem}"
    def tipo_origem
      return 'tribunal' if origem == '0000'
      return 'competencia_delegada_ou_residual' if origem == '9999'
      origem.start_with?('9') ? 'turma_recursal' : 'unidade_primeiro_grau'
    end

    private

    def invalid! = raise(Juridico::Error.new('invalid_cnj', 'Número CNJ inválido: verifique formato, campos e dígito verificador.'))
  end
end
