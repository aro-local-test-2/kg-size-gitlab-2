# frozen_string_literal: true

FactoryBot.define do
  factory :pm_license, class: "PackageMetadata::License" do
    sequence(:spdx_identifier) { |n| "OLDAP-2.#{n}" }
    spdx_expression { nil }

    initialize_with do
      if spdx_expression.present? && spdx_identifier.nil?
        PackageMetadata::License.find_or_initialize_by(spdx_expression: spdx_expression)
      else
        PackageMetadata::License.find_or_initialize_by(spdx_identifier: spdx_identifier)
      end
    end

    trait :with_expression do
      spdx_identifier { nil }
      spdx_expression { "MIT OR Apache-2.0" }
    end
  end
end
