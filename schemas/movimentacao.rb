# frozen_string_literal: true
module Schemas
  class Movimentacao < Base
    FIELDS = %i[codigo descricao data complementos].freeze
    def validate!
      required_string!(:descricao)
      DateTime.iso8601(@values.fetch(:data))
      raise ArgumentError unless @values[:complementos].is_a?(Hash)
    end
  end
end
