# frozen_string_literal: true
module Tribunais
  module TRF1
    class Client < Datajud::Client
      def initialize(http:, mapper: Mapper.new, **options)
        super(tribunal: 'TRF1', http: http, mapper: mapper, **options)
      end
    end
  end
end
