# frozen_string_literal: true

# Verifies a signal declares the label GraphQL resolves for it (used in
# `missingSignals` and `signalBreakdown` text) and a label for each of the
# dimensions it extracts.
#
# label            - the signal's own label, e.g. 'Test coverage'
# dimension_labels - a Hash of dimension name => its label, e.g.
#                     { uncovered_lines: 'Uncovered changed lines' }
RSpec.shared_examples 'a signal with dimensions' do |label, dimension_labels|
  it "declares '#{label}' as its label" do
    expect(described_class.label).to eq(label)
  end

  dimension_labels.each do |expected_dimension_name, expected_dimension_label|
    it "declares '#{expected_dimension_label}' as the label for its #{expected_dimension_name} dimension" do
      dimension = described_class.dimensions[expected_dimension_name]

      aggregate_failures do
        expect(dimension).not_to be_nil
        expect(dimension.label).to eq(expected_dimension_label)
      end
    end
  end
end
