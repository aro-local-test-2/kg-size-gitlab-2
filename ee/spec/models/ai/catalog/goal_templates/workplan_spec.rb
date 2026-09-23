# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Catalog::GoalTemplates::Workplan, feature_category: :duo_agent_platform do
  let_it_be(:project) { create(:project) }
  let_it_be(:work_item) { create(:work_item, project: project) }

  describe '.resolve' do
    subject(:goal) { described_class.resolve(resource: work_item) }

    it 'names the target work item by URL' do
      expect(goal).to eq("Generate a workplan for the work item at #{Gitlab::UrlBuilder.build(work_item)}.")
    end

    it 'ignores event_type and user_input' do
      expect(described_class.resolve(resource: work_item, event_type: :mention, user_input: 'x')).to eq(goal)
    end

    it 'raises ArgumentError when resource is nil' do
      expect { described_class.resolve(resource: nil) }.to raise_error(ArgumentError, /resource must not be nil/)
    end
  end
end
