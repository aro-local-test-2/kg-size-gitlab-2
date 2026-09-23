# frozen_string_literal: true

module Gitlab
  module Duo
    module RiskClassification
      module DomainsRegistry
        extend ActiveSupport::Concern

        included do |base|
          base.class_attribute(:registered_domains, default: [])
        end

        class_methods do
          def register_domain(domain_module)
            self.registered_domains += [domain_module]
          end
        end
      end
    end
  end
end
