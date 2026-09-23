# frozen_string_literal: true

module Analytics
  module KnowledgeGraph
    module Settings
      SETTINGS = {
        orbit_auto_index_root_namespace: {
          type: :boolean,
          default: false,
          label: -> { s_('Orbit|Index root namespaces automatically') }
        }
      }.freeze

      class << self
        def all_settings
          SETTINGS
        end

        def boolean_settings
          SETTINGS.select { |_, config| config[:type] == :boolean }
        end
      end
    end
  end
end
