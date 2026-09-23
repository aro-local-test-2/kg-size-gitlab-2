# frozen_string_literal: true

FactoryBot.define do
  factory :ai_compliance_anthropic_integration, class: 'Ai::Compliance::Anthropic::Integration' do
    namespace { association(:group) }
    api_key { 'sk-ant-api01-test-key' }
  end
end
