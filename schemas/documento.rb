# frozen_string_literal: true
module Schemas
  class Documento < Base
    FIELDS = %i[id_externo tipo descricao data url].freeze
    def validate!
      required_string!(:id_externo)
      DateTime.iso8601(@values[:data]) if @values[:data]
      if @values[:url]
        uri = URI.parse(@values[:url])
        raise ArgumentError unless uri.is_a?(URI::HTTPS) && uri.host && !uri.host.empty? && !uri.userinfo
      end
    end
  end
end
