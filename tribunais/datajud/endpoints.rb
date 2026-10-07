# frozen_string_literal: true
module Tribunais
  module Datajud
    ENDPOINTS = {
      'TRF1' => 'https://api-publica.datajud.cnj.jus.br/api_publica_trf1/_search',
      'TJMT' => 'https://api-publica.datajud.cnj.jus.br/api_publica_tjmt/_search',
      'STJ' => 'https://api-publica.datajud.cnj.jus.br/api_publica_stj/_search'
    }.freeze
  end
end
