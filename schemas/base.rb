# frozen_string_literal: true
require 'json'
require 'time'
module Schemas
  class Base
    def initialize(**values)
      unknown = values.keys - self.class::FIELDS
      raise ArgumentError, "Campos desconhecidos: #{unknown.join(', ')}" unless unknown.empty?
      @values = self.class::FIELDS.to_h { |key| [key, values[key]] }
      validate!
    end
    def to_h = JSON.parse(JSON.generate(@values))
    def validate!; end

    private

    def required_string!(key)
      value = @values[key]
      raise ArgumentError, "Campo obrigatório: #{key}" unless value.is_a?(String) && !value.empty?
    end
  end
end
