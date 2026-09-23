# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Dora::DeploymentFrequencyMetric, feature_category: :devops_reports do
  describe '#data_queries' do
    subject(:data_queries) { described_class.new(environment, date.to_date).data_queries }

    let_it_be(:project) { create(:project, :repository) }
    let_it_be(:environment) { create(:environment, project: project) }
    let_it_be(:date) { 1.day.ago }

    around do |example|
      freeze_time { example.run }
    end

    it 'returns number of finished successful deployments' do
      # Matching deployments
      create(:deployment, :success, environment: environment, finished_at: date.beginning_of_day)
      create(:deployment, :success, environment: environment, finished_at: date)
      create(:deployment, :success, environment: environment, finished_at: date.end_of_day)

      # Not matching deployments
      create(:deployment, :failed, environment: environment, finished_at: date) # failed deployment
      create(:deployment, :success, environment: environment, finished_at: date - 1.day) # different day
      create(:deployment, :success, environment: environment, finished_at: date + 1.day) # different day
      create(:deployment, :success, finished_at: date + 1.day) # different environment

      expect(data_queries.size).to eq 1
      expect(Deployment.connection.execute(data_queries[:deployment_frequency]).first['count']).to be 3
    end
  end
end
