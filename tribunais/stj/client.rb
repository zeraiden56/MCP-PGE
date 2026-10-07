# frozen_string_literal: true
module Tribunais
  module STJ
    class Client < Datajud::Client
      def initialize(http:, mapper: Mapper.new, **options)
        super(tribunal: 'STJ', http: http, mapper: mapper, **options)
      end
    end
  end
end
