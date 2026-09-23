# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::PipelineExecutionPolicyConfigLink, feature_category: :security_policy_management do
  subject { create(:security_pipeline_execution_policy_config_link) }

  describe 'associations' do
    it { is_expected.to belong_to(:project) }
    it { is_expected.to belong_to(:security_policy) }

    it { is_expected.to validate_uniqueness_of(:security_policy).scoped_to(:project_id) }
  end

  describe 'validations' do
    describe '#same_organization' do
      let_it_be(:security_policy) { create(:security_policy) }
      let_it_be(:policy_organization) { security_policy.source.organization }

      context 'when the project belongs to the same organization as the policy' do
        let_it_be(:project) { create(:project, organization: policy_organization) }

        it 'is valid' do
          config_link = build(:security_pipeline_execution_policy_config_link,
            project: project, security_policy: security_policy)

          expect(config_link).to be_valid
        end
      end

      context 'when the project belongs to a different organization than the policy' do
        let_it_be(:project) { create(:project, organization: create(:organization)) }

        it 'is invalid' do
          config_link = build(:security_pipeline_execution_policy_config_link,
            project: project, security_policy: security_policy)

          expect(config_link).not_to be_valid
          expect(config_link.errors[:project])
            .to include('must belong to the same organization as the policy')
        end
      end

      context 'when project is missing' do
        it 'does not raise and skips the check' do
          config_link = build(:security_pipeline_execution_policy_config_link,
            project: nil, security_policy: security_policy)

          expect { config_link.valid? }.not_to raise_error
          expect(config_link.errors[:project]).not_to include('must belong to the same organization as the policy')
        end
      end
    end
  end

  describe '.for_project' do
    let_it_be(:project1) { create(:project) }
    let_it_be(:project2) { create(:project) }
    let_it_be(:security_policy) { create(:security_policy) }

    before do
      create(:security_pipeline_execution_policy_config_link, project: project1, security_policy: security_policy)
    end

    it 'returns links for the specified project' do
      result = described_class.for_project(project1)

      expect(result.count).to eq(1)
      expect(result.first.project).to eq(project1)
    end

    it 'returns an empty relation if no links exist for the project' do
      result = described_class.for_project(project2)

      expect(result).to be_empty
    end
  end
end
