# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Duo::RiskClassification::Signals::AuthorExperience, feature_category: :duo_code_review do
  let_it_be(:project) { create(:project) }
  let_it_be(:author) { create(:user) }
  let_it_be(:merge_request) { create(:merge_request, source_project: project, author: author) }

  subject(:signal) { described_class.new(merge_request) }

  it_behaves_like 'a signal with dimensions', 'Author experience', {
    unfamiliar_author: 'How new the author is to this project'
  }

  describe '#available?' do
    it { is_expected.to be_available }

    context 'when the author is gone' do
      before do
        allow(merge_request).to receive(:author_id).and_return(nil)
      end

      it { is_expected.not_to be_available }
    end
  end

  describe '#extract' do
    context 'when the author has never merged here' do
      it 'reports maximum risk' do
        expect(signal.extract[:unfamiliar_author]).to eq(1.0)
      end
    end

    context 'when the author has merged a few times' do
      before do
        create_list(:merge_request, 2, :merged, :unique_branches, source_project: project, author: author)
      end

      it 'reports partial risk' do
        expect(signal.extract[:unfamiliar_author]).to eq(0.9)
      end
    end

    context 'when someone else has merged here' do
      before do
        create(:merge_request, :merged, :unique_branches, source_project: project, author: create(:user))
      end

      it 'does not credit the author' do
        expect(signal.extract[:unfamiliar_author]).to eq(1.0)
      end
    end

    context 'when the author has merged more than the saturation point' do
      before do
        stub_const("#{described_class}::MERGED_SATURATES_AT", 2)

        create_list(:merge_request, 3, :merged, :unique_branches, source_project: project, author: author)
      end

      it 'reports no risk' do
        expect(signal.extract[:unfamiliar_author]).to eq(0.0)
      end
    end
  end
end
