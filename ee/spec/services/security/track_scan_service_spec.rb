# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::TrackScanService, feature_category: :security_policy_management do
  let_it_be(:user) { create(:user) }
  let_it_be(:project) { create(:project, :public) }
  let_it_be(:pipeline) { create(:ci_pipeline, project: project, user: user) }

  let_it_be_with_reload(:build) { create(:ee_ci_build, pipeline: pipeline, user: user) }

  describe '#execute' do
    subject { described_class.new(build).execute }

    context 'report has all metadata' do
      let_it_be(:dast_artifact) { create(:ee_ci_job_artifact, :dast, job: build) }

      before do
        allow(Digest::SHA256).to receive(:hexdigest).and_return('82fc6391e4be61e03e51fa8c5c6bfc32b3d3f0065ad2fe0a01211606952b8d82')
      end

      it 'tracks the scan event', :snowplow, :unlimited_max_formatted_output_length do
        subject

        expect_snowplow_event(
          category: 'secure::scan',
          action: 'scan',
          context: [{
            schema: described_class::SECURE_SCAN_SCHEMA_URL,
            data: {
              analyzer: 'a-dast-scanner',
              analyzer_vendor: 'GitLab',
              analyzer_version: '1.0.0',
              end_time: '2022-08-10T22:37:00',
              findings_count: 24,
              scan_type: 'dast',
              scanner: 'a-dast-scanner',
              scanner_vendor: 'GitLab',
              scanner_version: '1.0.0',
              start_time: '2022-08-10T22:37:00',
              status: 'success',
              report_schema_version: '15.0.6'
            }
          }],
          idempotency_key: '82fc6391e4be61e03e51fa8c5c6bfc32b3d3f0065ad2fe0a01211606952b8d82',
          user: user,
          project: project.id,
          label: 'a-dast-scanner',
          property: 'dast')
      end
    end

    context 'report is missing metadata' do
      let_it_be(:dast_artifact) { create(:ee_ci_job_artifact, :dast_missing_scan_field, job: build) }

      before do
        allow(Digest::SHA256).to receive(:hexdigest).and_return('62bc6c62686b327dbf420f8891e1418406b60f49e574b6ff22f4d6a272dbc595')
      end

      it 'tracks the scan event', :snowplow do
        subject

        expect_snowplow_event(
          category: 'secure::scan',
          action: 'scan',
          context: [{
            schema: described_class::SECURE_SCAN_SCHEMA_URL,
            data: {
              analyzer: nil,
              analyzer_vendor: nil,
              analyzer_version: nil,
              end_time: nil,
              findings_count: 1,
              scan_type: 'dast',
              scanner: "zaproxy",
              scanner_vendor: nil,
              scanner_version: nil,
              start_time: nil,
              status: 'success',
              report_schema_version: '15.0.6'
            }
          }],
          idempotency_key: '62bc6c62686b327dbf420f8891e1418406b60f49e574b6ff22f4d6a272dbc595',
          user: user,
          project: project.id,
          label: nil,
          property: 'dast')
      end
    end

    context 'when the build has a SARIF artifact with two same-type (sast) tool runs' do
      let_it_be(:sarif_artifact) { create(:ee_ci_job_artifact, :sarif_multi_run_sast, job: build) }

      before do
        allow(Digest::SHA256).to receive(:hexdigest).and_call_original
        allow(Digest::SHA256).to receive(:hexdigest)
          .with("#{project.id}::#{build.id}::sast::semgrep").and_return('semgrep-key')
        allow(Digest::SHA256).to receive(:hexdigest)
          .with("#{project.id}::#{build.id}::sast::eslint").and_return('eslint-key')
      end

      it 'emits two distinct secure::scan events, one per scanner identity', :snowplow, :aggregate_failures do
        subject

        expect_snowplow_event(
          category: 'secure::scan',
          action: 'scan',
          context: [{
            schema: described_class::SECURE_SCAN_SCHEMA_URL,
            data: hash_including(scan_type: 'sast', scanner: 'semgrep', findings_count: 1)
          }],
          idempotency_key: 'semgrep-key',
          user: user,
          project: project.id,
          label: nil,
          property: 'sast')

        expect_snowplow_event(
          category: 'secure::scan',
          action: 'scan',
          context: [{
            schema: described_class::SECURE_SCAN_SCHEMA_URL,
            data: hash_including(scan_type: 'sast', scanner: 'eslint', findings_count: 1)
          }],
          idempotency_key: 'eslint-key',
          user: user,
          project: project.id,
          label: nil,
          property: 'sast')
      end
    end

    context 'when the build has both a native sast artifact and a SARIF artifact inferring sast' do
      let_it_be(:sast_artifact) { create(:ee_ci_job_artifact, :sast, job: build) }
      let_it_be(:sarif_artifact) { create(:ee_ci_job_artifact, :sarif_multi_type, job: build) }

      before do
        allow(Digest::SHA256).to receive(:hexdigest).and_call_original
        allow(Digest::SHA256).to receive(:hexdigest)
          .with("#{project.id}::#{build.id}::sast::2022-08-10T21:37:00").and_return('native-sast-key')
        allow(Digest::SHA256).to receive(:hexdigest)
          .with("#{project.id}::#{build.id}::sast::semgrep").and_return('sarif-sast-key')
      end

      it 'emits two distinct sast events from the two sources', :snowplow, :aggregate_failures do
        subject

        expect_snowplow_event(
          category: 'secure::scan',
          action: 'scan',
          context: [{
            schema: described_class::SECURE_SCAN_SCHEMA_URL,
            data: hash_including(scan_type: 'sast', scanner: 'find_sec_bugs')
          }],
          idempotency_key: 'native-sast-key',
          user: user,
          project: project.id,
          label: 'find_sec_bugs_analyzer',
          property: 'sast')

        expect_snowplow_event(
          category: 'secure::scan',
          action: 'scan',
          context: [{
            schema: described_class::SECURE_SCAN_SCHEMA_URL,
            data: hash_including(scan_type: 'sast', scanner: 'semgrep')
          }],
          idempotency_key: 'sarif-sast-key',
          user: user,
          project: project.id,
          label: nil,
          property: 'sast')
      end
    end

    context 'when the build has a SARIF artifact fanning out into multiple scan types' do
      let_it_be(:sarif_artifact) { create(:ee_ci_job_artifact, :sarif_multi_type, job: build) }

      before do
        allow(Digest::SHA256).to receive(:hexdigest).and_call_original
        allow(Digest::SHA256).to receive(:hexdigest)
          .with("#{project.id}::#{build.id}::sast::semgrep").and_return('sast-key')
        allow(Digest::SHA256).to receive(:hexdigest)
          .with("#{project.id}::#{build.id}::secret_detection::semgrep").and_return('secret-key')
      end

      it 'emits one event per typed sub-report with correct data', :snowplow, :aggregate_failures do
        subject

        expect_snowplow_event(
          category: 'secure::scan',
          action: 'scan',
          context: [{
            schema: described_class::SECURE_SCAN_SCHEMA_URL,
            data: {
              analyzer: nil,
              analyzer_vendor: nil,
              analyzer_version: nil,
              end_time: nil,
              findings_count: 1,
              scan_type: 'sast',
              scanner: 'semgrep',
              scanner_vendor: nil,
              scanner_version: '1.50.0',
              start_time: nil,
              status: 'success',
              report_schema_version: nil
            }
          }],
          idempotency_key: 'sast-key',
          user: user,
          project: project.id,
          label: nil,
          property: 'sast')

        expect_snowplow_event(
          category: 'secure::scan',
          action: 'scan',
          context: [{
            schema: described_class::SECURE_SCAN_SCHEMA_URL,
            data: {
              analyzer: nil,
              analyzer_vendor: nil,
              analyzer_version: nil,
              end_time: nil,
              findings_count: 1,
              scan_type: 'secret_detection',
              scanner: 'semgrep',
              scanner_vendor: nil,
              scanner_version: '1.50.0',
              start_time: nil,
              status: 'success',
              report_schema_version: nil
            }
          }],
          idempotency_key: 'secret-key',
          user: user,
          project: project.id,
          label: nil,
          property: 'secret_detection')
      end
    end

    context 'when the build has an empty SARIF artifact' do
      let_it_be(:sarif_artifact) { create(:ee_ci_job_artifact, :sarif_empty_runs, job: build) }

      before do
        allow(Digest::SHA256).to receive(:hexdigest).and_call_original
        allow(Digest::SHA256).to receive(:hexdigest)
          .with("#{project.id}::#{build.id}::sarif::").and_return('sarif-key')
      end

      it 'emits a single sarif event with no findings', :snowplow, :aggregate_failures do
        subject

        expect_snowplow_event(
          category: 'secure::scan',
          action: 'scan',
          context: [{
            schema: described_class::SECURE_SCAN_SCHEMA_URL,
            data: {
              analyzer: nil,
              analyzer_vendor: nil,
              analyzer_version: nil,
              end_time: nil,
              findings_count: 0,
              scan_type: 'sarif',
              scanner: nil,
              scanner_vendor: nil,
              scanner_version: nil,
              start_time: nil,
              status: 'success',
              report_schema_version: nil
            }
          }],
          idempotency_key: 'sarif-key',
          user: user,
          project: project.id,
          label: nil,
          property: 'sarif')
      end
    end
  end

  describe '#normalize_time' do
    subject(:normalize_time) { described_class.new(build).send(:normalize_time, value) }

    context 'when value already matches the schema format' do
      let(:value) { '2022-08-10T22:37:00' }

      it 'returns the value unchanged' do
        expect(normalize_time).to eq('2022-08-10T22:37:00')
      end
    end

    context 'when value has a Z (UTC) suffix' do
      let(:value) { '2022-08-10T22:37:00Z' }

      it 'strips the suffix and returns the UTC time' do
        expect(normalize_time).to eq('2022-08-10T22:37:00')
      end
    end

    context 'when value has a positive timezone offset' do
      let(:value) { '2022-08-11T02:37:00+04:00' }

      it 'converts to UTC before stripping the offset' do
        expect(normalize_time).to eq('2022-08-10T22:37:00')
      end
    end

    context 'when value has a negative timezone offset' do
      let(:value) { '2022-08-10T18:37:00-04:00' }

      it 'converts to UTC before stripping the offset' do
        expect(normalize_time).to eq('2022-08-10T22:37:00')
      end
    end

    context 'when value has fractional seconds and a Z suffix' do
      let(:value) { '2022-08-10T22:37:00.123Z' }

      it 'truncates fractional seconds and returns the UTC time' do
        expect(normalize_time).to eq('2022-08-10T22:37:00')
      end
    end

    context 'when value is nil' do
      let(:value) { nil }

      it { is_expected.to be_nil }
    end

    context 'when value is an empty string' do
      let(:value) { '' }

      it 'returns the value unchanged' do
        expect(normalize_time).to eq('')
      end
    end

    context 'when value is unparseable' do
      let(:value) { 'not-a-timestamp' }

      it { is_expected.to be_nil }
    end
  end
end
