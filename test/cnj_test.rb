# frozen_string_literal: true
require_relative 'test_helper'
class CNJTest < Minitest::Test
  def test_official_example_and_leading_zeros
    parsed = Tribunais::CNJ.new('0000832-35.2018.4.01.3202')
    assert_equal '00008323520184013202', parsed.normalizado
    assert_equal '3202', parsed.origem
    assert_equal '4', parsed.segmento
    assert_equal '01', parsed.regiao
    assert_equal 'unidade_primeiro_grau', parsed.tipo_origem
  end
  def test_rejects_bad_format_checksum_and_region
    [nil, 123, '', '0000832-34.2018.4.01.3202', 'x00008323520184013202',
     ' 00008323520184013202', '0000832.35.2018.4.01.3202', cnj('4', '99'),
     cnj('3', '00', '0001'), cnj('1', '01', '0000'), cnj('0', '00')].each do |value|
      error_code('invalid_cnj') { Tribunais::CNJ.new(value) }
    end
  end
  def test_origin_types
    assert_equal 'tribunal', Tribunais::CNJ.new(cnj('3', '00', '0000')).tipo_origem
    assert_equal 'turma_recursal', Tribunais::CNJ.new(cnj('8', '11', '9001')).tipo_origem
    assert_equal 'competencia_delegada_ou_residual', Tribunais::CNJ.new(cnj('4', '01', '9999')).tipo_origem
  end
  def test_resolver_all_initial_courts
    clients = %w[TRF1 TJMT STJ STF].to_h { |t| [t, Object.new] }
    resolver = Tribunais::TribunalResolver.new(clients)
    [['TRF1','4','01','3202'],['TJMT','8','11','0001'],['STJ','3','00','0000'],['STF','1','00','0000']].each do |tribunal, segment, region, origin|
      result = resolver.resolve(cnj(segment, region, origin))
      assert_equal tribunal, result.tribunal
      assert_same clients[tribunal], result.client
      assert_equal origin, result.cnj.origem
    end
  end
  def test_resolver_does_not_route_every_region_to_trf1
    error_code('unsupported_tribunal') { Tribunais::TribunalResolver.new({}).resolve(cnj('4', '06')) }
  end
end
