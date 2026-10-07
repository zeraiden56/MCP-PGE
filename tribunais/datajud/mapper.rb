# frozen_string_literal: true
module Tribunais
  module Datajud
    class Mapper
      def map(hit, cnj:, tribunal:, url:, consulted_at:)
        source = hit.fetch('_source')
        unless source['nivelSigilo'] == 0
          raise Juridico::Error.new('non_public_record', 'Registro sem confirmação de publicidade; consulta rejeitada.')
        end
        unless source.fetch('numeroProcesso') == cnj.normalizado && source.fetch('tribunal') == tribunal
          raise ArgumentError
        end
        source_id = source['id'] || hit.fetch('_id')
        movements = source.fetch('movimentos', []).map do |m|
          Schemas::Movimentacao.new(codigo: m['codigo'], descricao: m.fetch('nome'),
            data: timestamp(m.fetch('dataHora')), complementos: {
              'tabelados' => m.fetch('complementosTabelados', []),
              'orgao_julgador' => m['orgaoJulgador']
            }).to_h
        end.uniq.sort_by { |m| [m['data'], m['codigo'].to_s, m['descricao']] }
        Schemas::Processo.new(numero_cnj: cnj.formatado, tribunal: tribunal, tribunal_origem: tribunal,
          id_origem: source_id, grau: source.fetch('grau'), classe: source.fetch('classe').fetch('nome'),
          assuntos: source.fetch('assuntos', []).flatten.map { |a| a.fetch('nome') }.uniq,
          orgao_julgador: source.fetch('orgaoJulgador').fetch('nome'),
          data_ajuizamento: timestamp(source.fetch('dataAjuizamento')), situacao: nil,
          partes: [], movimentacoes: movements, documentos: [], fonte_consulta: 'datajud',
          fonte: { 'sistema' => 'datajud', 'sistema_origem' => source.dig('sistema', 'nome'),
                   'consultado_em' => consulted_at.utc.iso8601(6), 'url_origem' => url,
                   'atualizado_na_fonte_em' => optional_timestamp(source['dataHoraUltimaAtualizacao']) }).to_h
      rescue KeyError, ArgumentError, TypeError, NoMethodError
        raise Juridico::Error.new('invalid_response', 'Metadados processuais inválidos ou divergentes.', http_status: 200)
      end

      private

      def optional_timestamp(value) = value.nil? ? nil : timestamp(value)
      def timestamp(value)
        raise ArgumentError unless value.is_a?(String)
        if value.match?(/\A[0-9]{14}\z/)
          # Datas sem fuso não ganham precisão geográfica inventada.
          DateTime.strptime(value, '%Y%m%d%H%M%S').strftime('%Y-%m-%dT%H:%M:%S')
        else
          DateTime.iso8601(value)
          value
        end
      end
    end
  end
end
