# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Duo::RiskClassification::Signals::Base, feature_category: :duo_code_review do
  include I18nHelper

  using RSpec::Parameterized::TableSyntax

  let(:merge_request) { build(:merge_request) }

  subject(:signal) { described_class.new(merge_request) }

  describe '.set_label' do
    it 'is nil by default, since not every signal has UI copy yet' do
      expect(described_class.label).to be_nil
    end

    it 'sets the label a subclass declares' do
      subclass = Class.new(described_class) { set_label 'a label' }

      expect(subclass.label).to eq('a label')
    end

    it 'strips the namespace prefix from a namespaced string when no translation is available' do
      subclass = Class.new(described_class) { set_label N_('RiskClassification|a label') }

      expect(subclass.label).to eq('a label')
    end

    it 'returns the translated string when a translation is available for the active locale' do
      subclass = Class.new(described_class) { set_label N_('RiskClassification|a label') }

      with_stubbed_translations('de', { 'RiskClassification|a label' => 'ein Label' }) do
        expect(subclass.label).to eq('ein Label')
      end
    end
  end

  describe '.add_dimension' do
    it 'has no dimensions by default' do
      expect(described_class.dimensions).to eq({})
    end

    it 'stores a dimension keyed by name, defaulting method_name to the name' do
      subclass = Class.new(described_class) { add_dimension :churn, 'a label' }

      dimension = subclass.dimensions[:churn]

      aggregate_failures do
        expect(dimension.label).to eq('a label')
        expect(dimension.method_name).to eq(:churn)
      end
    end

    it 'strips the namespace prefix from a namespaced dimension label when no translation is available' do
      subclass = Class.new(described_class) { add_dimension :churn, N_('RiskClassification|a label') }

      expect(subclass.dimensions[:churn].label).to eq('a label')
    end

    it 'returns the translated dimension label when a translation is available for the active locale' do
      subclass = Class.new(described_class) { add_dimension :churn, N_('RiskClassification|a label') }

      with_stubbed_translations('de', { 'RiskClassification|a label' => 'ein Label' }) do
        expect(subclass.dimensions[:churn].label).to eq('ein Label')
      end
    end

    it 'stores the given method_name when the value comes from a differently named method' do
      subclass = Class.new(described_class) { add_dimension :churn, 'a label', :churn_ratio }

      expect(subclass.dimensions[:churn].method_name).to eq(:churn_ratio)
    end

    it 'does not leak dimensions between subclasses' do
      first = Class.new(described_class) { add_dimension :churn, 'a label' }
      second = Class.new(described_class) { add_dimension :breadth, 'another label' }

      aggregate_failures do
        expect(first.dimensions.keys).to contain_exactly(:churn)
        expect(second.dimensions.keys).to contain_exactly(:breadth)
      end
    end
  end

  describe '#available?' do
    it 'raises NotImplementedError, since concrete signals must define this' do
      expect { signal.available? }.to raise_error(NotImplementedError)
    end
  end

  describe '#extract' do
    let(:no_dimension_signal) do
      Class.new(described_class)
    end

    let(:direct_method_dimension_signal) do
      Class.new(described_class) do
        add_dimension :churn, 'a label'

        def churn
          0.5
        end
      end
    end

    let(:aliased_method_dimension_signal) do
      Class.new(described_class) do
        add_dimension :churn, 'a label', :churn_ratio

        def churn_ratio
          0.5
        end
      end
    end

    where(:signal, :extracted) do
      ref(:no_dimension_signal) | {}
      ref(:direct_method_dimension_signal) | { churn: 0.5 }
      ref(:aliased_method_dimension_signal) | { churn: 0.5 }
    end

    with_them do
      it 'extracts the dimensions using the existing methods' do
        expect(signal.new(merge_request).extract).to eq(extracted)
      end
    end
  end

  describe '#ramp' do
    where(:value, :saturation_at, :expected) do
      [
        [0, 100, 0.0],
        [-1, 100, 0.0],
        [50, 0, 0.0],
        [50, -1, 0.0],
        [50, 100, 0.5],
        [100, 100, 1.0],
        [500, 100, 1.0]
      ]
    end

    with_them do
      it 'saturates at 1.0 and floors at 0.0' do
        expect(signal.send(:ramp, value, saturation_at)).to eq(expected)
      end
    end
  end
end
