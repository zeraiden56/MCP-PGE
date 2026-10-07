# frozen_string_literal: true
require_relative 'test_helper'
class SchemasTest < Minitest::Test
  def test_party_keeps_document_optional_and_validates_name
    p = Schemas::Parte.new(nome: 'Pessoa sintética', tipo: 'autor', polo: 'ativo', documento: nil).to_h
    assert_equal %w[documento nome polo tipo], p.keys.sort
    assert_nil p['documento']
    assert_raises(ArgumentError) { Schemas::Parte.new(nome: '') }
    assert_raises(ArgumentError) { Schemas::Parte.new(nome: 'Teste', cpf: 'omitido') }
  end
  def test_document_does_not_allow_unsafe_links
    ['http://example.test/doc', 'javascript:alert(1)', 'https://user:pass@example.test/doc', 'https:///path'].each do |url|
      assert_raises(ArgumentError) { Schemas::Documento.new(id_externo: 'x', url: url) }
    end
    doc = Schemas::Documento.new(id_externo: 'x', url: 'https://example.test/doc', data: '2026-01-02').to_h
    assert_equal 'https://example.test/doc', doc['url']
  end
  def test_movement_validates_date_and_complements
    assert_raises(ArgumentError) { Schemas::Movimentacao.new(descricao: 'Teste', data: '2026-02-30T12:00:00Z', complementos: {}) }
    assert_raises(ArgumentError) { Schemas::Movimentacao.new(descricao: 'Teste', data: '2026-02-01T12:00:00Z', complementos: []) }
  end
  def test_canonical_process_contains_required_fields_and_is_a_copy
    process = canonical
    schema = Schemas::Processo.new(**process.transform_keys(&:to_sym))
    copy = schema.to_h
    copy['fonte']['sistema'] = 'alterado'
    assert_equal 'datajud', schema.to_h['fonte']['sistema']
    invalid = process.merge('movimentacoes' => nil)
    assert_raises(ArgumentError) { Schemas::Processo.new(**invalid.transform_keys(&:to_sym)) }
  end
end
