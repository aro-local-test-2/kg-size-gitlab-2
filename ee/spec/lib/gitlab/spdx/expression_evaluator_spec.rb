# frozen_string_literal: true

require 'fast_spec_helper'

RSpec.describe Gitlab::SPDX::ExpressionEvaluator, feature_category: :software_composition_analysis do
  let(:evaluator) do
    Class.new do
      include Gitlab::SPDX::ExpressionEvaluator

      def satisfied_by?(expression, allowed_names)
        evaluate(::Gitlab::SPDX::ExpressionParser.new(expression).parse.node, allowed_names)
      end

      private

      def evaluate_leaf(value, allowed_names)
        allowed_names.include?(value)
      end
    end.new
  end

  describe '#evaluate' do
    using RSpec::Parameterized::TableSyntax

    where(:expression, :allowed_names, :expected) do
      'MIT'                                        | %w[MIT]                    | true
      'MIT'                                        | %w[Apache-2.0]             | false
      'MIT AND Apache-2.0'                         | %w[MIT Apache-2.0]         | true
      'MIT AND Apache-2.0'                         | %w[MIT]                    | false
      'MIT OR Apache-2.0'                          | %w[Apache-2.0]             | true
      'MIT OR Apache-2.0'                          | %w[MIT Apache-2.0]         | true
      'MIT OR Apache-2.0'                          | %w[Zlib]                   | false
      'mit or apache-2.0'                          | %w[apache-2.0]             | true
      '(MIT OR Zlib) AND Apache-2.0'               | %w[Zlib Apache-2.0]        | true
      '(MIT OR Zlib) AND Apache-2.0'               | %w[Zlib]                   | false
      'GPL-2.0 WITH Classpath-exception-2.0'       | ['GPL-2.0 WITH Classpath-exception-2.0'] | true
      'GPL-2.0 WITH Classpath-exception-2.0'       | %w[GPL-2.0]                | true
      'GPL-2.0 WITH Classpath-exception-2.0'       | %w[MIT]                    | false
      'LGPL-2.0+'                                  | %w[LGPL-2.0+]              | true
      'LGPL-2.0+'                                  | %w[LGPL-2.0]               | false
      'MIT License'                                | ['MIT License']            | true
      'MIT License'                                | %w[MIT]                    | false
    end

    with_them do
      it { expect(evaluator.satisfied_by?(expression, allowed_names)).to eq(expected) }
    end
  end

  describe 'COMPOUND_NODE_TYPES' do
    it 'lists the node types that are not a single license identifier' do
      expect(described_class::COMPOUND_NODE_TYPES).to eq(%i[and or with plus])
    end
  end
end
