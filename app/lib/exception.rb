module Glim
  class Error < ::RuntimeError
    attr_reader :message, :previous

    def initialize(message, previous = nil)
      @message, @previous = message, previous
    end

    def messages
      res = [ @message ]
      e = self
      while e.respond_to?(:previous) && (e = e.previous)
        res << e.message
      end
      res
    end
  end
end