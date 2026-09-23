# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Vulnerabilities::Flag, feature_category: :vulnerability_management do
  describe 'associations' do
    it { is_expected.to belong_to(:finding).class_name('Vulnerabilities::Finding').with_foreign_key('vulnerability_occurrence_id').required }
    it { is_expected.to belong_to(:workflow).class_name('::Ai::DuoWorkflows::Workflow').optional }
  end

  describe 'validations' do
    subject { build(:vulnerabilities_flag) }

    it { is_expected.to validate_length_of(:origin).is_at_most(255) }
    it { is_expected.to validate_length_of(:description).is_at_most(100000) }
    it { is_expected.to validate_presence_of(:flag_type) }
    it { is_expected.to validate_uniqueness_of(:flag_type).scoped_to(:vulnerability_occurrence_id, :origin).ignoring_case_sensitivity }
    it { is_expected.to validate_inclusion_of(:confidence_score).in_range(0.0..1.0) }
    it { is_expected.to define_enum_for(:flag_type).with_values(false_positive: 0) }
    it { is_expected.to define_enum_for(:status).with_values(described_class::FALSE_POSITIVE_DETECTION_STATUSES) }
  end

  describe '#initialize' do
    it 'creates a valid flag with flag_type attribute' do
      flag = described_class.new(flag_type: described_class.flag_types[:false_positive], origin: 'post analyzer X', description: 'static string to sink', finding: build(:vulnerabilities_finding))
      expect(flag).to be_valid
    end
  end

  context 'with loose foreign key on vulnerability_flags.project_id' do
    it_behaves_like 'cleanup by a loose foreign key' do
      let_it_be(:parent) { create(:project) }
      let_it_be(:model) do
        create(:vulnerabilities_flag, project_id: parent.id, finding: create(:vulnerabilities_finding, project: parent))
      end
    end
  end

  describe '.by_finding_id' do
    let_it_be(:project) { create(:project) }
    let_it_be(:finding) { create(:vulnerabilities_finding, project: project) }
    let_it_be(:another_finding) { create(:vulnerabilities_finding, project: project) }
    let_it_be(:vulnerability_flag) { create(:vulnerabilities_flag, finding: finding) }
    let_it_be(:another_vulnerability_flag) { create(:vulnerabilities_flag, finding: another_finding) }

    subject { described_class.by_finding_id(finding.id) }

    it { is_expected.to contain_exactly(vulnerability_flag) }
  end

  describe '.latest' do
    let_it_be(:finding) { create(:vulnerabilities_finding) }
    let_it_be(:older_flag) { create(:vulnerabilities_flag, finding: finding, origin: 'origin_a', updated_at: 2.days.ago) }
    let_it_be(:newer_flag) { create(:vulnerabilities_flag, finding: finding, origin: 'origin_b', updated_at: 1.day.ago) }

    subject(:latest_flags) { described_class.where(finding: finding).latest }

    it 'returns flags ordered by updated_at descending' do
      expect(latest_flags).to eq([newer_flag, older_flag])
    end
  end

  describe '.with_status' do
    using RSpec::Parameterized::TableSyntax

    let_it_be(:finding) { create(:vulnerabilities_finding) }

    let_it_be(:detected_flag) do
      create(:vulnerabilities_flag, :false_positive, finding: finding, origin: 'o1', status: :detected_as_fp)
    end

    let_it_be(:dismissed_flag) do
      create(:vulnerabilities_flag, :false_positive, finding: finding, origin: 'o2', status: :dismissed)
    end

    let_it_be(:failed_flag) do
      create(:vulnerabilities_flag, :false_positive, finding: finding, origin: 'o3', status: :failed)
    end

    where(:status, :expected) do
      :detected_as_fp | -> { [detected_flag] }
      :dismissed      | -> { [dismissed_flag] }
      :failed         | -> { [failed_flag] }
    end

    with_them do
      subject(:scope) { described_class.with_status(status) }

      it 'returns only flags with the given status' do
        expect(scope).to match_array(instance_exec(&expected))
      end
    end
  end

  describe '#dismissable?' do
    let_it_be(:project) { build_stubbed(:project) }
    let_it_be(:finding) { build_stubbed(:vulnerabilities_finding, project: project) }

    it 'returns true for detected_as_fp status' do
      flag = build_stubbed(:vulnerabilities_flag, finding: finding, status: :detected_as_fp, confidence_score: 0.8, origin: 'o1')
      expect(flag.dismissable?).to be true
    end

    it 'returns true for detected_as_not_fp status' do
      flag = build_stubbed(:vulnerabilities_flag, finding: finding, status: :detected_as_not_fp, confidence_score: 0.0, origin: 'o2')
      expect(flag.dismissable?).to be true
    end

    it 'returns false for not_started status' do
      flag = build_stubbed(:vulnerabilities_flag, finding: finding, status: :not_started, confidence_score: 0.8, origin: 'o3')
      expect(flag.dismissable?).to be false
    end

    it 'returns false for dismissed status' do
      flag = build_stubbed(:vulnerabilities_flag, finding: finding, status: :dismissed, confidence_score: 0.0, origin: 'o4')
      expect(flag.dismissable?).to be false
    end

    it 'returns false for failed status' do
      flag = build_stubbed(:vulnerabilities_flag, finding: finding, status: :failed, confidence_score: 0.0, origin: 'o5')
      expect(flag.dismissable?).to be false
    end
  end

  describe '#triggers_resolution_workflow?' do
    let_it_be(:project) { build_stubbed(:project) }
    let_it_be(:finding) { build_stubbed(:vulnerabilities_finding, project: project) }

    it 'returns true for failed status' do
      flag = build_stubbed(:vulnerabilities_flag, finding: finding, status: :failed, confidence_score: 0.0, origin: 'o8')
      expect(flag.triggers_resolution_workflow?).to be true
    end

    it 'returns true for detected_as_not_fp status' do
      flag = build_stubbed(:vulnerabilities_flag, finding: finding, status: :detected_as_not_fp, confidence_score: 0.0, origin: 'o9')
      expect(flag.triggers_resolution_workflow?).to be true
    end

    it 'returns false for detected_as_fp status' do
      flag = build_stubbed(:vulnerabilities_flag, finding: finding, status: :detected_as_fp, confidence_score: 0.8, origin: 'o10')
      expect(flag.triggers_resolution_workflow?).to be false
    end

    it 'returns false for dismissed status' do
      flag = build_stubbed(:vulnerabilities_flag, finding: finding, status: :dismissed, confidence_score: 0.0, origin: 'o11')
      expect(flag.triggers_resolution_workflow?).to be false
    end

    context 'when a triage_and_remediation profile sets false_positive_confidence' do
      using RSpec::Parameterized::TableSyntax

      let_it_be(:confidence_group) { create(:group) }
      let_it_be(:confidence_project) { create(:project, group: confidence_group) }
      let_it_be(:confidence_finding) { create(:vulnerabilities_finding, project: confidence_project) }

      def attach_confidence(configuration_values)
        profile = create(:security_scan_profile, :triage_and_remediation, namespace: confidence_group,
          projects: [confidence_project])
        create(:security_scan_profile_trigger, scan_profile: profile, trigger_type: :sast_vulnerability_resolution,
          configuration_values: configuration_values)
      end

      before do
        stub_licensed_features(security_scan_profiles: true)
      end

      context 'when false_positive_confidence is not configured' do
        before_all do
          attach_confidence(severity_level: 'low')
        end

        where(:status, :result) do
          [
            [:detected_as_fp, false],
            [:detected_as_not_fp, true],
            [:failed, true],
            [:dismissed, false]
          ]
        end

        with_them do
          it 'falls back to the hardcoded status gate' do
            flag = build_stubbed(:vulnerabilities_flag, finding: confidence_finding, status: status)

            expect(flag.triggers_resolution_workflow?).to be(result)
          end
        end
      end

      context 'when likely_false_positive' do
        before_all do
          attach_confidence(false_positive_confidence: 'likely_false_positive')
        end

        where(:status, :result) do
          [
            [:detected_as_fp, true],
            [:detected_as_not_fp, false],
            [:failed, false],
            [:dismissed, false]
          ]
        end

        with_them do
          it 'matches the expected result for the required confidence' do
            flag = build_stubbed(:vulnerabilities_flag, finding: confidence_finding, status: status)

            expect(flag.triggers_resolution_workflow?).to be(result)
          end
        end
      end

      context 'when likely_not_false_positive' do
        before_all do
          attach_confidence(false_positive_confidence: 'likely_not_false_positive')
        end

        where(:status, :result) do
          [
            [:detected_as_fp, false],
            [:detected_as_not_fp, true],
            [:failed, false],
            [:dismissed, false]
          ]
        end

        with_them do
          it 'matches the expected result for the required confidence, excluding failed' do
            flag = build_stubbed(:vulnerabilities_flag, finding: confidence_finding, status: status)

            expect(flag.triggers_resolution_workflow?).to be(result)
          end
        end
      end
    end
  end

  describe '.last_false_positive_per_finding' do
    let_it_be(:project) { create(:project) }
    let_it_be(:finding1) { create(:vulnerabilities_finding, project: project) }
    let_it_be(:finding2) { create(:vulnerabilities_finding, project: project) }

    let_it_be(:f1_old) { create(:vulnerabilities_flag, :false_positive, finding: finding1, origin: 'o1') }
    let_it_be(:f1_new) { create(:vulnerabilities_flag, :false_positive, finding: finding1, origin: 'o2') }
    let_it_be(:f2_old) { create(:vulnerabilities_flag, :false_positive, finding: finding2, origin: 'o3') }
    let_it_be(:f2_new) { create(:vulnerabilities_flag, :false_positive, finding: finding2, origin: 'o4') }

    subject(:results) { described_class.last_false_positive_per_finding }

    it 'returns the latest flag per finding' do
      expect(results).to contain_exactly(f1_new, f2_new)
    end
  end

  describe '.pluck_with_limit' do
    let_it_be(:project) { create(:project) }
    let_it_be(:finding1) { create(:vulnerabilities_finding, project: project) }
    let_it_be(:finding2) { create(:vulnerabilities_finding, project: project) }

    let_it_be(:flag1) { create(:vulnerabilities_flag, finding: finding1) }
    let_it_be(:flag2) { create(:vulnerabilities_flag, finding: finding2) }

    it 'returns the requested columns limited by size' do
      expect(
        described_class.where(id: [flag1.id, flag2.id]).pluck_with_limit(2, :id, :flag_type)
      ).to match_array([
        [flag1.id, flag1.flag_type],
        [flag2.id, flag2.flag_type]
      ])
    end
  end

  describe 'after_commit callback for trigger_resolution_workflow' do
    let_it_be(:project) { create(:project) }
    let_it_be(:user) { create(:user) }
    let_it_be(:vulnerability) { create(:vulnerability, project: project, author: user) }
    let_it_be(:finding) { create(:vulnerabilities_finding, project: project, vulnerability: vulnerability) }

    context 'when a vulnerability flag gets created' do
      context 'when duo_sast_vr_workflow_enabled is disabled' do
        before do
          allow(project).to receive(:duo_sast_vr_workflow_enabled).and_return(false)
        end

        it 'does not trigger resolution workflow' do
          expect(::Vulnerabilities::TriggerResolutionWorkflowWorker)
            .not_to receive(:perform_async)

          create(:vulnerabilities_flag, finding: finding, status: :failed, origin: described_class::AI_SAST_FP_DETECTION_ORIGIN)
        end
      end

      context 'when origin is ai_sast_fp_detection' do
        before_all do
          project.project_setting.update!(duo_sast_vr_workflow_enabled: true)
        end

        context 'when status triggers resolution workflow' do
          context 'when finding is eligible for resolution workflow' do
            before do
              allow(finding).to receive(:eligible_for_resolution_workflow?).and_return(true)
              allow(Ability).to receive(:allowed?).and_call_original
              allow(Ability).to receive(:allowed?)
                .with(anything, :duo_workflow, project).and_return(true)
            end

            it 'triggers resolution workflow' do
              expect(::Vulnerabilities::TriggerResolutionWorkflowWorker)
                .to receive(:perform_async)
                      .with(anything)

              create(:vulnerabilities_flag, finding: finding, status: :failed, origin: described_class::AI_SAST_FP_DETECTION_ORIGIN)
            end

            context 'when author does not have duo_workflow permission' do
              before do
                allow(Ability).to receive(:allowed?).with(user, :duo_workflow, project).and_return(false)
              end

              it 'does not trigger resolution workflow' do
                expect(::Vulnerabilities::TriggerResolutionWorkflowWorker)
                  .not_to receive(:perform_async)

                create(:vulnerabilities_flag, finding: finding, status: :failed, origin: described_class::AI_SAST_FP_DETECTION_ORIGIN)
              end
            end

            context 'when finding has no vulnerability' do
              before do
                allow(finding).to receive(:vulnerability).and_return(nil)
              end

              it 'does not trigger resolution workflow' do
                expect(::Vulnerabilities::TriggerResolutionWorkflowWorker)
                  .not_to receive(:perform_async)

                create(:vulnerabilities_flag, finding: finding, status: :failed, origin: described_class::AI_SAST_FP_DETECTION_ORIGIN)
              end
            end

            context 'when author has duo_workflow permission' do
              before do
                allow(Ability).to receive(:allowed?).with(user, :duo_workflow, project).and_return(true)
              end

              it 'triggers resolution workflow' do
                expect(::Vulnerabilities::TriggerResolutionWorkflowWorker)
                  .to receive(:perform_async)
                        .with(anything)

                create(:vulnerabilities_flag, finding: finding, status: :failed, origin: described_class::AI_SAST_FP_DETECTION_ORIGIN)
              end
            end

            context 'with a latest bulk SAST FP execution' do
              let(:execution) do
                instance_double(
                  ::Vulnerabilities::BulkDuoWorkflow::ExecutionState,
                  contains_item?: contains_item
                )
              end

              before do
                allow(::Vulnerabilities::BulkDuoWorkflow::ExecutionState)
                  .to receive(:latest)
                        .with(
                          project_id: project.id,
                          workflow: ::Vulnerabilities::TriggerFalsePositiveDetectionWorkflowWorker::WORKFLOW_DEFINITION
                        )
                        .and_return(execution)
              end

              context 'when the execution contains the finding' do
                let(:contains_item) { true }

                it 'does not trigger resolution workflow' do
                  expect(::Vulnerabilities::TriggerResolutionWorkflowWorker)
                    .not_to receive(:perform_async)

                  create(
                    :vulnerabilities_flag,
                    finding: finding,
                    status: :failed,
                    origin: described_class::AI_SAST_FP_DETECTION_ORIGIN
                  )
                end
              end

              context 'when the execution does not contain the finding' do
                let(:contains_item) { false }

                it 'triggers resolution workflow' do
                  expect(::Vulnerabilities::TriggerResolutionWorkflowWorker)
                    .to receive(:perform_async)
                          .with(anything)

                  create(
                    :vulnerabilities_flag,
                    finding: finding,
                    status: :failed,
                    origin: described_class::AI_SAST_FP_DETECTION_ORIGIN
                  )
                end
              end
            end
          end

          context 'when finding is not eligible for resolution workflow' do
            before do
              allow(finding).to receive(:eligible_for_resolution_workflow?).and_return(false)
            end

            it 'does not trigger resolution workflow' do
              expect(::Vulnerabilities::TriggerResolutionWorkflowWorker)
                .not_to receive(:perform_async)

              create(:vulnerabilities_flag, finding: finding, status: :failed, origin: described_class::AI_SAST_FP_DETECTION_ORIGIN)
            end
          end
        end

        context 'when status is detected_as_fp' do
          it 'does not trigger resolution workflow' do
            expect(::Vulnerabilities::TriggerResolutionWorkflowWorker)
              .not_to receive(:perform_async)

            create(:vulnerabilities_flag, finding: finding, status: :detected_as_fp, origin: described_class::AI_SAST_FP_DETECTION_ORIGIN)
          end
        end

        context 'when status is dismissed' do
          it 'does not trigger resolution workflow' do
            expect(::Vulnerabilities::TriggerResolutionWorkflowWorker)
              .not_to receive(:perform_async)

            create(:vulnerabilities_flag, finding: finding, status: :dismissed, origin: described_class::AI_SAST_FP_DETECTION_ORIGIN)
          end
        end
      end

      context 'when origin is not ai_sast_fp_detection' do
        it 'does not trigger resolution workflow' do
          expect(::Vulnerabilities::TriggerResolutionWorkflowWorker)
            .not_to receive(:perform_async)

          create(:vulnerabilities_flag, finding: finding, status: :failed, origin: 'some_other_origin')
        end
      end

      context 'when no profile is attached' do
        using RSpec::Parameterized::TableSyntax

        let_it_be(:severity_project) { create(:project) }
        let_it_be_with_reload(:severity_vulnerability) do
          create(:vulnerability, :sast, project: severity_project, author: user)
        end

        let_it_be(:severity_finding) do
          create(:vulnerabilities_finding, project: severity_project, vulnerability: severity_vulnerability)
        end

        let_it_be(:severity_triggered_workflow) do
          create(:vulnerability_triggered_workflow,
            vulnerability_occurrence: severity_finding,
            workflow: create(:duo_workflows_workflow, project: severity_project),
            workflow_name: :sast_fp_detection)
        end

        before do
          severity_project.project_setting.update!(duo_sast_vr_workflow_enabled: true)
          severity_vulnerability.update!(severity: severity)
          allow(Ability).to receive(:allowed?).and_call_original
          allow(Ability).to receive(:allowed?).with(anything, :duo_workflow, severity_project).and_return(true)
        end

        where(:severity, :should_trigger) do
          [
            [:critical, true],
            [:high, true],
            [:medium, false],
            [:low, false]
          ]
        end

        with_them do
          it 'respects high or critical gate on the automatic path' do
            if should_trigger
              expect(::Vulnerabilities::TriggerResolutionWorkflowWorker).to receive(:perform_async).with(anything)
            else
              expect(::Vulnerabilities::TriggerResolutionWorkflowWorker).not_to receive(:perform_async)
            end

            create(:vulnerabilities_flag, finding: severity_finding, status: :failed,
              origin: described_class::AI_SAST_FP_DETECTION_ORIGIN)
          end
        end
      end

      context 'when a triage_and_remediation scan profile drives the trigger' do
        using RSpec::Parameterized::TableSyntax

        let_it_be(:profile_group) { create(:group) }
        let_it_be(:profile_project) { create(:project, group: profile_group) }
        let_it_be(:profile_vulnerability) do
          create(:vulnerability, :sast, :high, project: profile_project, author: user)
        end

        let_it_be(:profile_finding) do
          create(:vulnerabilities_finding, project: profile_project, vulnerability: profile_vulnerability)
        end

        let_it_be(:scan_profile) do
          create(:security_scan_profile, :triage_and_remediation, namespace: profile_group)
        end

        let_it_be(:scan_profile_project) do
          create(:security_scan_profile_project, scan_profile: scan_profile, project: profile_project)
        end

        before do
          stub_licensed_features(security_scan_profiles: true)
          create(:security_scan_profile_trigger, scan_profile: scan_profile,
            trigger_type: :sast_vulnerability_resolution, configuration_values: { run_mode: run_mode })
          allow(profile_finding).to receive(:eligible_for_resolution_workflow?).and_return(true)
          allow(Ability).to receive(:allowed?).and_call_original
          allow(Ability).to receive(:allowed?).with(anything, :duo_workflow, profile_project).and_return(true)
        end

        where(:run_mode, :should_trigger) do
          'auto'   | true
          'manual' | false
        end

        with_them do
          it 'enables the flow without duo_sast_vr_workflow_enabled and honours the profile run mode' do
            if should_trigger
              expect(::Vulnerabilities::TriggerResolutionWorkflowWorker).to receive(:perform_async).with(anything)
            else
              expect(::Vulnerabilities::TriggerResolutionWorkflowWorker).not_to receive(:perform_async)
            end

            create(:vulnerabilities_flag, finding: profile_finding, status: :failed,
              origin: described_class::AI_SAST_FP_DETECTION_ORIGIN)
          end
        end
      end
    end

    context 'when updating an existing vulnerability flag' do
      let_it_be_with_reload(:existing_flag) { create(:vulnerabilities_flag, finding: finding, status: :not_started, origin: described_class::AI_SAST_FP_DETECTION_ORIGIN) }

      before_all do
        project.project_setting.update!(duo_sast_vr_workflow_enabled: true)
      end

      before do
        existing_flag.finding = finding
      end

      context 'when only non-relevant fields are updated' do
        it 'does not trigger resolution workflow' do
          expect(::Vulnerabilities::TriggerResolutionWorkflowWorker)
            .not_to receive(:perform_async)

          existing_flag.update!(description: 'Updated description')
        end
      end

      context 'when status is updated to a trigger status' do
        before do
          allow(finding).to receive(:eligible_for_resolution_workflow?).and_return(true)
          allow(Ability).to receive(:allowed?).and_call_original
          allow(Ability).to receive(:allowed?)
            .with(anything, :duo_workflow, project).and_return(true)
        end

        it 'triggers resolution workflow' do
          expect(::Vulnerabilities::TriggerResolutionWorkflowWorker)
            .to receive(:perform_async)
                  .with(existing_flag.id)

          existing_flag.update!(status: :failed)
        end
      end

      context 'when origin changes to non-ai origin' do
        it 'does not trigger resolution workflow' do
          expect(::Vulnerabilities::TriggerResolutionWorkflowWorker)
            .not_to receive(:perform_async)

          existing_flag.update!(origin: 'some_other_origin')
        end
      end

      context 'when status changes to a non-trigger status' do
        it 'does not trigger resolution workflow' do
          expect(::Vulnerabilities::TriggerResolutionWorkflowWorker)
            .not_to receive(:perform_async)

          existing_flag.update!(status: :detected_as_fp)
        end
      end
    end
  end

  describe '#should_trigger_resolution_workflow?' do
    let_it_be(:project) { create(:project) }
    let_it_be(:user) { create(:user) }
    let_it_be(:vulnerability) { create(:vulnerability, project: project, author: user) }
    let_it_be(:finding) { create(:vulnerabilities_finding, project: project, vulnerability: vulnerability) }
    let_it_be(:flag, freeze: false) { create(:vulnerabilities_flag, finding: finding, status: :failed, origin: described_class::AI_SAST_FP_DETECTION_ORIGIN) }

    before_all do
      project.project_setting.update!(duo_sast_vr_workflow_enabled: true)
    end

    before do
      allow(finding).to receive(:eligible_for_resolution_workflow?).and_return(true)
      allow(Ability).to receive(:allowed?).and_call_original
      allow(Ability).to receive(:allowed?)
        .with(anything, :duo_workflow, project).and_return(true)
    end

    context 'when status is updated' do
      it 'considers status change as trigger for resolution workflow' do
        flag # ensure created
        flag.status = :failed
        allow(flag).to receive_messages(saved_change_to_id?: false, saved_change_to_status?: true)

        expect(flag.send(:should_trigger_resolution_workflow?)).to be true
      end
    end

    context 'when non-status fields are updated' do
      it 'does not consider non-status changes as trigger' do
        flag # ensure created
        allow(flag).to receive_messages(saved_change_to_id?: false, saved_change_to_status?: false)

        expect(flag.send(:should_trigger_resolution_workflow?)).to be false
      end
    end
  end
end
