# frozen_string_literal: true

module Gitlab
  module Duo
    module RiskClassification
      module ExtractorsRegistry
        extend ActiveSupport::Concern

        included do |base|
          base.class_attribute(:registered_extractors, default: [])
        end

        class_methods do
          def register_extractor(extractor_class)
            self.registered_extractors += [extractor_class]
          end
        end
      end
    end
  end
end
