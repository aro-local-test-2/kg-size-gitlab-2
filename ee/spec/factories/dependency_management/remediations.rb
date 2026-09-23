# frozen_string_literal: true

FactoryBot.define do
  factory :dependency_management_remediation, class: 'DependencyManagement::Remediation' do
    project
    purl_type { :npm }
    package_name { 'lodash' }
    input_file_path { 'package.json' }
    current_version { '4.17.11' }
    target_version { '4.17.21' }
    state { :open }

    trait :dismissed do
      state { :dismissed }
    end

    trait :merged do
      state { :merged }
    end

    trait :with_merge_request do
      merge_request { association(:merge_request, source_project: project) }
    end
  end
end
