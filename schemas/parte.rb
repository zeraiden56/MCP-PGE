# frozen_string_literal: true
module Schemas
  class Parte < Base
    FIELDS = %i[nome tipo polo documento].freeze
    def validate! = required_string!(:nome)
  end
end
