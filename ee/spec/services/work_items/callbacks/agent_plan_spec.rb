# frozen_string_literal: true

require 'spec_helper'

RSpec.describe WorkItems::Callbacks::AgentPlan, feature_category: :team_planning do
  let_it_be(:user) { create(:user) }
  let_it_be(:project) { create(:project, reporters: user) }
  let_it_be_with_reload(:work_item) { create(:work_item, project: project, author: user) }

  let(:current_user) { user }
  let(:params) { {} }
  let(:callback) { described_class.new(issuable: work_item, current_user: current_user, params: params) }

  shared_examples 'agent plan is unchanged' do
    it 'does not change agent plan' do
      expect { subject }.not_to change { work_item.reload.agent_plan&.content }
    end
  end

  describe '#before_create' do
    subject(:before_create_callback) { callback.before_create }

    context 'when content param is present' do
      let(:params) { { content: 'New plan content' } }

      it 'builds an agent plan', :aggregate_failures do
        before_create_callback

        expect(work_item.agent_plan).to be_present
        expect(work_item.agent_plan.content).to eq('New plan content')
        expect(work_item.agent_plan.namespace).to eq(work_item.namespace)
      end

      it 'enables AI planning' do
        before_create_callback

        expect(work_item.agent_plan.ai_planning_enabled).to be(true)
      end

      context 'when widget does not exist in type' do
        before do
          allow(callback).to receive(:excluded_in_new_type?).and_return(true)
        end

        it 'does not build an agent plan' do
          before_create_callback

          expect(work_item.agent_plan).to be_nil
        end
      end
    end

    context 'when only readiness_score param is present' do
      let(:params) { { readiness_score: 40 } }

      context 'when workplan_score is enabled' do
        before do
          stub_feature_flags(workplan_score: true)
        end

        it 'builds an agent plan with the score and blank content' do
          before_create_callback

          expect(work_item.agent_plan).to be_present
          expect(work_item.agent_plan.readiness_score).to eq(40)
          expect(work_item.agent_plan.content).to be_blank
        end

        it 'enables AI planning so the score is visible' do
          before_create_callback

          expect(work_item.agent_plan.ai_planning_enabled).to be(true)
        end
      end

      context 'when workplan_score is disabled' do
        before do
          stub_feature_flags(workplan_score: false)
        end

        it 'raises a callback error' do
          expect { before_create_callback }.to raise_error(
            ::Issuable::Callbacks::Base::Error,
            /readiness_score.*workplan_score/
          )
        end
      end
    end

    context 'when only readiness_score_feedback param is present' do
      let(:params) { { readiness_score_feedback: 'Add acceptance criteria.' } }

      context 'when workplan_score is enabled' do
        before do
          stub_feature_flags(workplan_score: true)
        end

        it 'builds an agent plan with the feedback and blank content' do
          before_create_callback

          expect(work_item.agent_plan).to be_present
          expect(work_item.agent_plan.readiness_score_feedback).to eq('Add acceptance criteria.')
          expect(work_item.agent_plan.content).to be_blank
        end
      end

      context 'when workplan_score is disabled' do
        before do
          stub_feature_flags(workplan_score: false)
        end

        it 'raises a callback error' do
          expect { before_create_callback }.to raise_error(
            ::Issuable::Callbacks::Base::Error,
            /readiness_score_feedback.*workplan_score/
          )
        end
      end
    end

    context 'when content and readiness_score params are both present' do
      let(:params) { { content: 'Plan content', readiness_score: 40 } }

      context 'when workplan_score is disabled' do
        before do
          stub_feature_flags(workplan_score: false)
        end

        it 'raises a callback error without persisting content' do
          expect { before_create_callback }.to raise_error(::Issuable::Callbacks::Base::Error)
          expect(work_item.agent_plan).to be_nil
        end
      end
    end

    context 'when readiness_score param is absent and workplan_score is disabled' do
      let(:params) { { content: 'Plan content' } }

      before do
        stub_feature_flags(workplan_score: false)
      end

      it 'builds an agent plan with the content' do
        before_create_callback

        expect(work_item.agent_plan).to be_present
        expect(work_item.agent_plan.content).to eq('Plan content')
      end
    end

    context 'when content param is not present' do
      let(:params) { {} }

      it_behaves_like 'agent plan is unchanged'
    end

    context 'when ai_planning_enabled param is given' do
      # AI planning is create-only, so the callback must see the unsaved record
      # that the real create path hands it.
      let(:work_item) { build(:work_item, project: project, author: user) }

      context 'when it is true' do
        let(:params) { { ai_planning_enabled: true } }

        it 'builds an agent plan with ai_planning_enabled set to true', :aggregate_failures do
          before_create_callback

          expect(work_item.agent_plan).to be_present
          expect(work_item.agent_plan.ai_planning_enabled).to be(true)
          expect(work_item.agent_plan.content).to be_blank
        end

        context 'when the workplan flag is disabled' do
          before do
            stub_feature_flags(workplan: false)
          end

          it 'does not build an agent plan' do
            before_create_callback

            expect(work_item.agent_plan).to be_nil
          end
        end
      end

      context 'when it is false' do
        let(:params) { { ai_planning_enabled: false } }

        it 'does not build an agent plan' do
          before_create_callback

          expect(work_item.agent_plan).to be_nil
        end
      end

      context 'when it is true and content is also supplied' do
        let(:params) { { ai_planning_enabled: true, content: 'Plan content' } }

        it 'builds an agent plan with both content and ai_planning_enabled', :aggregate_failures do
          before_create_callback

          expect(work_item.agent_plan).to be_present
          expect(work_item.agent_plan.ai_planning_enabled).to be(true)
          expect(work_item.agent_plan.content).to eq('Plan content')
        end
      end
    end

    context 'when user does not have permission' do
      let_it_be(:guest) { create(:user) }

      let(:current_user) { guest }
      let(:params) { { content: 'New plan content' } }

      it_behaves_like 'agent plan is unchanged'
    end
  end

  describe '#before_update' do
    subject(:before_update_callback) { callback.before_update }

    # Fresh per example: externally-stored fields don't roll back, so a shared id leaks saves.
    let!(:agent_plan) { create(:work_item_agent_plan, work_item: work_item, content: 'Original content') }

    context 'when content param is present' do
      let(:params) { { content: 'Updated content' } }

      it 'updates the agent plan content' do
        before_update_callback

        expect(work_item.agent_plan.content).to eq('Updated content')
      end

      it 'enables AI planning' do
        expect { before_update_callback }
          .to change { work_item.agent_plan.ai_planning_enabled }.from(false).to(true)
      end
    end

    context 'when the content is cleared' do
      let(:params) { { content: '' } }

      it 'does not enable AI planning' do
        before_update_callback

        expect(work_item.agent_plan.ai_planning_enabled).to be(false)
      end

      context 'when AI planning was already enabled' do
        before do
          work_item.agent_plan.ai_planning_enabled = true
        end

        it 'keeps AI planning enabled' do
          before_update_callback

          expect(work_item.agent_plan.ai_planning_enabled).to be(true)
        end
      end
    end

    context 'when content param is not present' do
      let(:params) { {} }

      it 'does not change agent plan content' do
        before_update_callback

        expect(work_item.agent_plan.content).to eq('Original content')
      end

      context 'when widget does not exist in type' do
        before do
          allow(callback).to receive(:excluded_in_new_type?).and_return(true)
        end

        it 'destroys the existing agent plan' do
          before_update_callback

          expect(work_item.reload.agent_plan).to be_nil
        end
      end
    end

    context 'when content exceeds maximum length' do
      let(:params) { { content: 'x' * (WorkItems::AgentPlan::CONTENT_LENGTH_MAX + 1) } }

      it 'raises a callback error' do
        expect { before_update_callback }.to raise_error(
          ::Issuable::Callbacks::Base::Error, /is too long/
        )
      end
    end

    context 'when readiness_score param is present' do
      let(:params) { { readiness_score: 65 } }

      context 'when workplan_score is enabled' do
        before do
          stub_feature_flags(workplan_score: true)
        end

        it 'updates the readiness score without changing content' do
          before_update_callback

          expect(work_item.agent_plan.readiness_score).to eq(65)
          expect(work_item.agent_plan.content).to eq('Original content')
        end

        context 'when the plan has no content yet' do
          let(:params) { { readiness_score: 30 } }

          before do
            work_item.agent_plan.content = ''
          end

          it 'enables AI planning so the score is visible' do
            expect { before_update_callback }
              .to change { work_item.agent_plan.ai_planning_enabled }.from(false).to(true)
          end
        end

        context 'when the score is out of range' do
          let(:params) { { readiness_score: 150 } }

          it 'raises a callback error' do
            expect { before_update_callback }.to raise_error(::Issuable::Callbacks::Base::Error)
          end
        end
      end

      context 'when workplan_score is disabled' do
        before do
          stub_feature_flags(workplan_score: false)
        end

        it 'raises a callback error' do
          expect { before_update_callback }.to raise_error(
            ::Issuable::Callbacks::Base::Error,
            /readiness_score.*workplan_score/
          )
        end
      end
    end

    context 'when content and readiness_score params are both present' do
      let(:params) { { content: 'Updated content', readiness_score: 65 } }

      context 'when workplan_score is disabled' do
        before do
          stub_feature_flags(workplan_score: false)
        end

        it 'raises a callback error without applying content' do
          expect { before_update_callback }.to raise_error(::Issuable::Callbacks::Base::Error)
          expect(work_item.agent_plan.content).to eq('Original content')
        end
      end
    end

    context 'when neither readiness_score nor readiness_score_feedback is present and workplan_score is disabled' do
      let(:params) { { content: 'Updated content' } }

      before do
        stub_feature_flags(workplan_score: false)
      end

      it 'updates the content without error' do
        before_update_callback

        expect(work_item.agent_plan.content).to eq('Updated content')
      end
    end

    context 'when readiness_score_feedback param is present' do
      let(:params) { { readiness_score_feedback: 'Add acceptance criteria.' } }

      context 'when workplan_score is enabled' do
        before do
          stub_feature_flags(workplan_score: true)
        end

        it 'updates the feedback without changing content' do
          before_update_callback

          expect(work_item.agent_plan.readiness_score_feedback).to eq('Add acceptance criteria.')
          expect(work_item.agent_plan.content).to eq('Original content')
        end

        context 'when the staged record is saved' do
          let(:params) { { readiness_score_feedback: 'Add **acceptance criteria**.' } }

          # The callback only assigns the raw field; the HTML the read path serves
          # comes from the markdown cache refreshing on save.
          it 'refreshes the cached HTML rendering' do
            before_update_callback

            plan = work_item.agent_plan
            plan.save!

            expect(plan.reload.readiness_score_feedback_html)
              .to match(%r{<strong[^>]*>acceptance criteria</strong>})
          end
        end

        context 'when feedback exceeds the maximum length' do
          let(:params) { { readiness_score_feedback: 'x' * (WorkItems::AgentPlan::CONTENT_LENGTH_MAX + 1) } }

          it 'raises a callback error' do
            expect { before_update_callback }.to raise_error(::Issuable::Callbacks::Base::Error)
          end
        end
      end

      context 'when workplan_score is disabled' do
        before do
          stub_feature_flags(workplan_score: false)
        end

        it 'raises a callback error' do
          expect { before_update_callback }.to raise_error(
            ::Issuable::Callbacks::Base::Error,
            /readiness_score_feedback.*workplan_score/
          )
        end
      end
    end

    context 'when readiness_score_feedback and content params are both present' do
      let(:params) { { content: 'Updated content', readiness_score_feedback: 'Good plan.' } }

      context 'when workplan_score is enabled' do
        before do
          stub_feature_flags(workplan_score: true)
        end

        it 'updates both fields' do
          before_update_callback

          expect(work_item.agent_plan.content).to eq('Updated content')
          expect(work_item.agent_plan.readiness_score_feedback).to eq('Good plan.')
        end
      end

      context 'when workplan_score is disabled' do
        before do
          stub_feature_flags(workplan_score: false)
        end

        it 'raises a callback error without applying content' do
          expect { before_update_callback }.to raise_error(::Issuable::Callbacks::Base::Error)
          expect(work_item.agent_plan.content).to eq('Original content')
        end
      end
    end

    context 'when readiness_score and readiness_score_feedback params are both present' do
      let(:params) { { readiness_score: 80, readiness_score_feedback: 'Add acceptance criteria.' } }

      before do
        stub_feature_flags(workplan_score: true)
      end

      # The agent scores and explains in one call, so both attributes must land on
      # the same record: a single save keeps score and feedback from disagreeing.
      it 'stages both attributes on one record for a single save', :aggregate_failures do
        before_update_callback

        plan = work_item.agent_plan

        expect(plan.changed).to include('readiness_score', 'readiness_score_feedback')
        expect(plan.content).to eq('Original content')

        expect { plan.save! }.not_to change { WorkItems::AgentPlan.count }

        plan.reload
        expect(plan.readiness_score).to eq(80)
        expect(plan.readiness_score_feedback).to eq('Add acceptance criteria.')
      end
    end

    context 'when ai_planning_enabled param is true' do
      let(:params) { { ai_planning_enabled: true } }

      it 'does not enable AI planning on an existing work item' do
        before_update_callback

        expect(work_item.agent_plan.ai_planning_enabled).to be(false)
      end
    end

    context 'when user does not have permission' do
      let_it_be(:guest) { create(:user) }

      let(:current_user) { guest }
      let(:params) { { content: 'Updated content' } }

      it_behaves_like 'agent plan is unchanged'
    end
  end

  describe '#after_save_commit' do
    let(:tracking_service) { instance_double(::Gitlab::WorkItems::Instrumentation::TrackingService) }

    before do
      allow(::Gitlab::WorkItems::Instrumentation::TrackingService)
        .to receive_messages(new: tracking_service, current_source: 'api')
      allow(tracking_service).to receive(:execute)
    end

    shared_examples 'tracks agent plan event' do |event_const_name|
      it "tracks the #{event_const_name} event with a source dimension", :aggregate_failures do
        callback.after_save_commit

        expect(::Gitlab::WorkItems::Instrumentation::TrackingService).to have_received(:new).with(
          work_item: work_item,
          current_user: current_user,
          event: ::Gitlab::WorkItems::Instrumentation::EventActions.const_get(event_const_name, false),
          extra_properties: { source: 'api' }
        )
        expect(tracking_service).to have_received(:execute)
      end
    end

    shared_examples 'does not track agent plan event' do
      it 'does not call TrackingService' do
        callback.after_save_commit

        expect(::Gitlab::WorkItems::Instrumentation::TrackingService).not_to have_received(:new)
      end
    end

    context 'when before_create added an agent plan' do
      let(:params) { { content: 'New plan content' } }

      before do
        callback.before_create
      end

      it_behaves_like 'tracks agent plan event', :AGENT_PLAN_CREATE
    end

    # Regression: a score-only call persists a row with blank content; the
    # subsequent call that first sets content must still emit CREATE, not UPDATE.
    context 'when a score-only call preceded the first content-setting call' do
      before do
        stub_feature_flags(workplan_score: true)

        score_callback = described_class.new(
          issuable: work_item,
          current_user: current_user,
          params: { readiness_score: 50 }
        )
        score_callback.before_create
        work_item.agent_plan.save! # persist the score-only row

        work_item.reload
        callback.before_update
      end

      let(:params) { { content: 'First real content' } }

      it_behaves_like 'tracks agent plan event', :AGENT_PLAN_CREATE
    end

    context 'when before_update updated an existing agent plan content' do
      let(:params) { { content: 'Updated content' } }

      before do
        create(:work_item_agent_plan, work_item: work_item, content: 'Original content')
        work_item.reload
        callback.before_update
      end

      it_behaves_like 'tracks agent plan event', :AGENT_PLAN_UPDATE
    end

    context 'when before_update reapplied identical content' do
      let(:params) { { content: 'Original content' } }

      before do
        create(:work_item_agent_plan, work_item: work_item, content: 'Original content')
        work_item.reload
        callback.before_update
      end

      it_behaves_like 'does not track agent plan event'
    end

    context 'when before_update destroyed the agent plan (widget excluded in new type)' do
      let(:params) { {} }

      before do
        create(:work_item_agent_plan, work_item: work_item, content: 'Original content')
        work_item.reload
        allow(callback).to receive(:excluded_in_new_type?).and_return(true)
        callback.before_update
      end

      it_behaves_like 'tracks agent plan event', :AGENT_PLAN_DESTROY
    end

    context 'when before_update is excluded_in_new_type but no agent plan exists' do
      let(:params) { {} }

      before do
        allow(callback).to receive(:excluded_in_new_type?).and_return(true)
        callback.before_update
      end

      it_behaves_like 'does not track agent plan event'
    end

    context 'when no agent plan change occurred' do
      let(:params) { {} }

      before do
        callback.before_update
      end

      it_behaves_like 'does not track agent plan event'
    end

    context 'when only readiness_score_feedback changed (no content change)' do
      let(:params) { { readiness_score_feedback: 'New feedback.' } }

      before do
        stub_feature_flags(workplan_score: true)
        create(:work_item_agent_plan, work_item: work_item, content: 'Original content')
        work_item.reload
        callback.before_update
      end

      it_behaves_like 'does not track agent plan event'
    end

    context 'when readiness_score and readiness_score_feedback changed together' do
      let(:params) { { readiness_score: 80, readiness_score_feedback: 'New feedback.' } }

      before do
        stub_feature_flags(workplan_score: true)
        create(:work_item_agent_plan, work_item: work_item, content: 'Original content')
        work_item.reload
        callback.before_update
      end

      it_behaves_like 'does not track agent plan event'
    end
  end
end
