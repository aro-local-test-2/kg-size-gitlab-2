# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Duo::RiskClassification::SignalsExtractor, feature_category: :duo_code_review do
  include I18nHelper

  let_it_be(:merge_request) { build_stubbed(:merge_request) }

  let(:available_signal) do
    Class.new(Gitlab::Duo::RiskClassification::Signals::Base) do
      def self.signal_name
        'available_signal'
      end

      def available?
        true
      end

      def extract
        { churn: 0.5 }
      end
    end
  end

  let(:unavailable_signal) do
    Class.new(Gitlab::Duo::RiskClassification::Signals::Base) do
      def self.signal_name
        'unavailable_signal'
      end

      def available?
        false
      end

      def extract
        { never: 1.0 }
      end
    end
  end

  let(:mitigating_signal) do
    Class.new(Gitlab::Duo::RiskClassification::Signals::Base) do
      def self.signal_name
        'mitigating_signal'
      end

      mitigation!

      def available?
        true
      end

      def extract
        { feature_flag: 1.0 }
      end
    end
  end

  let(:raising_signal) do
    Class.new(Gitlab::Duo::RiskClassification::Signals::Base) do
      def self.signal_name
        'broken_signal'
      end

      def available?
        true
      end

      def extract
        raise 'boom'
      end
    end
  end

  # A subclass so registering test extractors does not mutate the real
  # registry: class_attribute copies on write.
  def extract(signals)
    extractor = Class.new(described_class) { self.registered_extractors = [] }
    signals.each { |signal| extractor.register_extractor(signal) }

    extractor.new(merge_request).execute
  end

  it 'namespaces values by signal name so keys cannot collide' do
    result = extract([available_signal])

    expect(result.signals).to eq({ 'available_signal.churn': 0.5 })
    expect(result.mitigations).to be_empty
    expect(result.missing).to be_empty
  end

  it 'keeps mitigations out of the risk signals' do
    result = extract([available_signal, mitigating_signal])

    expect(result.signals).to eq({ 'available_signal.churn': 0.5 })
    expect(result.mitigations).to eq({ 'mitigating_signal.feature_flag': 1.0 })
  end

  it 'records an unavailable mitigation as missing alongside the signals' do
    unavailable_mitigation = Class.new(mitigating_signal) do
      def self.signal_name
        'unavailable_mitigation'
      end

      def available?
        false
      end
    end

    result = extract([unavailable_mitigation])

    expect(result.mitigations).to be_empty
    expect(result.missing).to eq(['unavailable_mitigation'])
  end

  it 'records an unavailable signal as missing rather than as zero' do
    result = extract([unavailable_signal])

    expect(result.signals).to be_empty
    expect(result.missing).to eq(['unavailable_signal'])
  end

  it 'does not call extract on an unavailable signal' do
    instance = instance_double(unavailable_signal, available?: false)
    allow(unavailable_signal).to receive(:new).and_return(instance)

    expect(instance).not_to receive(:extract)

    extract([unavailable_signal])
  end

  context 'when a signal raises' do
    it 'records it as missing and keeps the other signals' do
      result = extract([available_signal, raising_signal])

      expect(result.signals).to eq({ 'available_signal.churn': 0.5 })
      expect(result.missing).to eq(['broken_signal'])
    end

    it 'reports the exception with the signal that failed' do
      expect(Gitlab::ErrorTracking).to receive(:track_exception).with(
        an_instance_of(RuntimeError),
        hash_including(merge_request_id: merge_request.id, signal: 'broken_signal')
      )

      extract([raising_signal])
    end
  end

  it 'declares a label for every registered signal and each of its dimensions' do
    aggregate_failures do
      described_class.registered_extractors.each do |signal_class|
        expect(signal_class.label).to be_present, "#{signal_class} declares no label"

        signal_class.dimensions.each do |name, dimension|
          expect(dimension.label).to be_present, "#{signal_class}##{name} dimension declares no label"
        end
      end
    end
  end

  it 'registers the full signal set' do
    expect(described_class.registered_extractors).to eq(
      [
        Gitlab::Duo::RiskClassification::Signals::DiffShape,
        Gitlab::Duo::RiskClassification::Signals::TestCoverage,
        Gitlab::Duo::RiskClassification::Signals::TestEvidence,
        Gitlab::Duo::RiskClassification::Signals::AiAuthorship,
        Gitlab::Duo::RiskClassification::Signals::DependencyManifest,
        Gitlab::Duo::RiskClassification::Signals::Ownership,
        Gitlab::Duo::RiskClassification::Signals::AuthorExperience,
        Gitlab::Duo::RiskClassification::Signals::Reversibility,
        Gitlab::Duo::RiskClassification::Signals::RolloutGuard,
        Gitlab::Duo::RiskClassification::Signals::Revert
      ]
    )
  end

  it 'declares every signal as a signal unless it opts into the mitigation channel' do
    mitigations = described_class.registered_extractors.select(&:mitigation?)

    expect(mitigations).to contain_exactly(
      Gitlab::Duo::RiskClassification::Signals::RolloutGuard,
      Gitlab::Duo::RiskClassification::Signals::Revert
    )
  end

  describe '.signal_class_for' do
    it 'finds a registered signal class by its signal_name' do
      expect(described_class.signal_class_for('test_coverage')).to eq(
        Gitlab::Duo::RiskClassification::Signals::TestCoverage
      )
    end

    it 'returns nil for a claim, which has no registered signal class' do
      expect(described_class.signal_class_for('touches_auth')).to be_nil
    end
  end

  describe '.label_for' do
    it 'resolves a dimension label for a "<signal>.<dimension>" key' do
      expect(described_class.label_for('test_coverage.uncovered_lines')).to eq('Uncovered changed lines')
    end

    it 'resolves the signal label for a bare signal key' do
      expect(described_class.label_for('test_coverage')).to eq('Test coverage')
    end

    it 'returns nil for a claim, which has no registered signal class' do
      expect(described_class.label_for('touches_auth')).to be_nil
    end

    it 'returns nil for a dimension its signal class never declared' do
      expect(described_class.label_for('diff_shape.nonexistent_dimension')).to be_nil
    end

    context 'when the locale is not English' do
      it 'resolves the translated dimension label for a "<signal>.<dimension>" key' do
        with_stubbed_translations(
          'de', { 'RiskClassification|Uncovered changed lines' => 'Nicht abgedeckte geänderte Zeilen' }
        ) do
          expect(described_class.label_for('test_coverage.uncovered_lines'))
            .to eq('Nicht abgedeckte geänderte Zeilen')
        end
      end

      it 'resolves the translated signal label for a bare signal key' do
        with_stubbed_translations('de', { 'RiskClassification|Test coverage' => 'Testabdeckung' }) do
          expect(described_class.label_for('test_coverage')).to eq('Testabdeckung')
        end
      end

      it 'returns nil for a claim, which has no registered signal class' do
        with_stubbed_translations('de', {}) do
          expect(described_class.label_for('touches_auth')).to be_nil
        end
      end
    end
  end
end
