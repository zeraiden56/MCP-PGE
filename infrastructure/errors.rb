# frozen_string_literal: true
module Juridico
  class Error < StandardError
    attr_reader :code, :http_status
    def initialize(code, message, http_status: nil)
      @code, @http_status = code, http_status
      super(message)
    end
  end
end
