# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoWorkflows::RunEvent, feature_category: :duo_agent_platform do
  let_it_be(:workflow) { create(:duo_workflows_workflow, :created) }

  subject(:event) { described_class.new(payload) }

  describe '#input?' do
    context 'with a symbol-keyed input' do
      let(:payload) { { type: :input, text: 'Fix the pipeline' } }

      it { expect(event.input?).to be(true) }
    end

    context 'with a string-keyed input' do
      let(:payload) { { 'type' => 'input', 'text' => 'Fix the pipeline' } }

      it { expect(event.input?).to be(true) }
    end

    context 'with blank text' do
      let(:payload) { { type: :input, text: '' } }

      it { expect(event.input?).to be(false) }
    end

    context 'with an extra key' do
      let(:payload) { { type: :input, text: 'Fix the pipeline', extra: true } }

      it { expect(event.input?).to be(false) }
    end

    context 'with the legacy goal type' do
      let(:payload) { { type: :goal, text: 'Fix the pipeline' } }

      it { expect(event.input?).to be(false) }
    end
  end

  describe '#approval?' do
    context 'with an approval' do
      let(:payload) { { type: :approval, approved: true } }

      it { expect(event.approval?).to be(true) }
    end

    context 'with a rejection message' do
      let(:payload) { { type: :approval, approved: false, message: 'No' } }

      it { expect(event.approval?).to be(true) }
    end

    context 'with a non-boolean decision' do
      let(:payload) { { type: :approval, approved: 'yes' } }

      it { expect(event.approval?).to be(false) }
    end

    context 'with a missing decision' do
      let(:payload) { { type: :approval, message: 'No' } }

      it { expect(event.approval?).to be(false) }
    end

    context 'with the legacy tool_approval type' do
      let(:payload) { { type: :tool_approval, approved: true } }

      it { expect(event.approval?).to be(false) }
    end
  end

  describe '#workhorse_approval' do
    context 'when approved' do
      let(:payload) { { type: :approval, approved: true } }

      it 'builds an empty approval' do
        expect(event.workhorse_approval).to eq({ 'approval' => {} })
      end
    end

    context 'when rejected' do
      let(:payload) { { type: :approval, approved: false, message: 'No' } }

      it 'builds a rejection with the message' do
        expect(event.workhorse_approval).to eq({ 'rejection' => { 'message' => 'No' } })
      end
    end
  end

  describe '#valid_for?' do
    context 'with a non-hash event' do
      let(:payload) { 'input' }

      it { expect(event.valid_for?(workflow)).to be(false) }
    end

    context 'with an input for a created session' do
      let(:payload) { { type: :input, text: 'Fix the pipeline' } }

      it { expect(event.valid_for?(workflow)).to be(true) }
    end

    context 'with an input for a session awaiting input' do
      let(:workflow) { create(:duo_workflows_workflow, :input_required) }
      let(:payload) { { type: :input, text: 'Please continue' } }

      it { expect(event.valid_for?(workflow)).to be(true) }
    end

    context 'with an input for a session awaiting an approval' do
      let(:workflow) { create(:duo_workflows_workflow, :tool_call_approval_required) }
      let(:payload) { { type: :input, text: 'Fix the pipeline' } }

      it { expect(event.valid_for?(workflow)).to be(false) }
    end

    context 'with an approval for a session awaiting a tool call approval' do
      let(:workflow) { create(:duo_workflows_workflow, :tool_call_approval_required) }
      let(:payload) { { type: :approval, approved: true } }

      it { expect(event.valid_for?(workflow)).to be(true) }
    end

    context 'with an approval for a session awaiting a plan approval' do
      let(:workflow) { create(:duo_workflows_workflow, :plan_approval_required) }
      let(:payload) { { type: :approval, approved: true } }

      it { expect(event.valid_for?(workflow)).to be(true) }
    end

    context 'with an approval for a session that is not awaiting one' do
      let(:payload) { { type: :approval, approved: true } }

      it { expect(event.valid_for?(workflow)).to be(false) }
    end
  end
end
