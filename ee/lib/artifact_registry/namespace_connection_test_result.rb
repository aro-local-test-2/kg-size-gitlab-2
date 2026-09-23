# frozen_string_literal: true

module ArtifactRegistry
  class NamespaceConnectionTestResult
    def initialize(attributes = {})
      @attributes = attributes || {}
    end

    def passed
      @attributes['passed'] == true
    end

    def http_status
      @attributes['http_status']
    end
  end
end
