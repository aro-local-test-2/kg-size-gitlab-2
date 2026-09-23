# frozen_string_literal: true

require 'fast_spec_helper'

RSpec.describe Search::Elastic::CompositePagination::Page, feature_category: :global_search do
  subject(:page) { described_class.new(records: %w[a b], first_key: { 'k' => 'a' }, last_key: { 'k' => 'b' }) }

  it 'enumerates as its records', :aggregate_failures do
    expect(page.to_a).to eq(%w[a b])
    expect(page.map(&:upcase)).to eq(%w[A B])
    expect(page.size).to eq(2)
    expect(page).to be_any
    expect(page).not_to be_empty
  end

  it 'carries the bucket key at either end of the rows', :aggregate_failures do
    expect(page.first_key).to eq({ 'k' => 'a' })
    expect(page.last_key).to eq({ 'k' => 'b' })
  end

  it 'reports another page when told there is one' do
    expect(described_class.new(records: %w[a], has_next_page: true)).to have_next_page
  end

  it 'defaults to an empty last page', :aggregate_failures do
    empty = described_class.new

    expect(empty).to be_empty
    expect(empty).not_to have_next_page
    expect(empty.first_key).to be_nil
    expect(empty.last_key).to be_nil
  end
end
