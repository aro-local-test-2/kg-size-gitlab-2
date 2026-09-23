# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'secrets_manager initializer', feature_category: :secrets_management do
  let(:configuration) { SecretsManagement::SecretsManagerClient.configuration }

  it 'configures the client host and base path' do
    expect(configuration.host).to eq('http://127.0.0.1:9800')
    expect(configuration.base_path).to eq('v1')
  end

  it 'reapplies the configuration after a code reload' do
    # A reload discards the class; the prepare callbacks are what run afterwards.
    SecretsManagement::SecretsManagerClient.instance_variable_set(:@configuration, nil)

    Rails.application.reloader.prepare!

    expect(configuration.host).to eq('http://127.0.0.1:9800')
    expect(configuration.base_path).to eq('v1')
  end
end
