# frozen_string_literal: true
module Tribunais
  module TJMT
    class Client < Datajud::Client
      def initialize(http:, mapper: Mapper.new, **options)
        super(tribunal: 'TJMT', http: http, mapper: mapper, **options)
      end
    end
  end
end
