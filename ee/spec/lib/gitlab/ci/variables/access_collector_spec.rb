# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Ci::Variables::AccessCollector, feature_category: :pipeline_composition do
  let_it_be(:project) { create(:project) }
  let_it_be(:group) { create(:group) }

  subject(:collector) { described_class.new }

  describe '#empty?' do
    it 'is empty when nothing was recorded' do
      expect(collector).to be_empty
    end

    it 'is not empty once an access was recorded' do
      collector.record(scope: project, key: 'TOKEN', hidden: false)

      expect(collector).not_to be_empty
    end
  end

  describe '#record' do
    it 'groups accessed keys by scope' do
      collector.record(scope: project, key: 'PROJECT_TOKEN', hidden: false)
      collector.record(scope: group, key: 'GROUP_TOKEN', hidden: false)

      expect(accesses).to contain_exactly(
        have_attributes(scope: project, accessed_keys: Set['PROJECT_TOKEN'], hidden_keys: Set.new),
        have_attributes(scope: group, accessed_keys: Set['GROUP_TOKEN'], hidden_keys: Set.new)
      )
    end

    it 'records hidden variables separately' do
      collector.record(scope: project, key: 'VISIBLE', hidden: false)
      collector.record(scope: project, key: 'HIDDEN', hidden: true)

      expect(accesses).to contain_exactly(
        have_attributes(accessed_keys: Set['VISIBLE'], hidden_keys: Set['HIDDEN'])
      )
    end

    it 'deduplicates repeated accesses of the same key' do
      2.times { collector.record(scope: project, key: 'TOKEN', hidden: false) }

      expect(accesses).to contain_exactly(have_attributes(accessed_keys: Set['TOKEN']))
    end

    context 'with the key limit stubbed' do
      before do
        stub_const("#{described_class}::MAX_KEYS_PER_SCOPE", 2)
      end

      it 'stops recording and marks the access as truncated once a key is dropped' do
        3.times { |i| collector.record(scope: project, key: "TOKEN_#{i}", hidden: false) }

        expect(accesses).to contain_exactly(
          have_attributes(accessed_keys: Set['TOKEN_0', 'TOKEN_1'], truncated?: true)
        )
      end

      it 'does not mark the access as truncated at exactly the limit' do
        2.times { |i| collector.record(scope: project, key: "TOKEN_#{i}", hidden: false) }

        expect(accesses).to contain_exactly(have_attributes(truncated?: false))
      end

      it 'does not mark the access as truncated when an already recorded key repeats' do
        2.times { |i| collector.record(scope: project, key: "TOKEN_#{i}", hidden: false) }
        collector.record(scope: project, key: 'TOKEN_0', hidden: false)

        expect(accesses).to contain_exactly(have_attributes(truncated?: false))
      end

      it 'counts hidden and accessed keys against the same limit' do
        collector.record(scope: project, key: 'VISIBLE', hidden: false)
        collector.record(scope: project, key: 'HIDDEN', hidden: true)
        collector.record(scope: project, key: 'DROPPED', hidden: false)

        expect(accesses).to contain_exactly(
          have_attributes(accessed_keys: Set['VISIBLE'], hidden_keys: Set['HIDDEN'], truncated?: true)
        )
      end
    end
  end

  def accesses
    collector.to_a
  end
end
