# frozen_string_literal: true

module ArtifactRegistry
  class ConnectionTestResult
    include TimeCoercion

    def initialize(attributes = {})
      @attributes = attributes || {}
    end

    def passed
      @attributes['passed'] == true
    end

    def http_status
      @attributes['http_status']
    end

    def last_health_status
      @attributes['last_health_status']
    end

    def last_health_checked_at
      parse_time(@attributes['last_health_checked_at'])
    end
  end
end
