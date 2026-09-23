# frozen_string_literal: true

require 'fast_spec_helper'

RSpec.describe Search::Elastic::CompositePagination::Paginator, feature_category: :global_search do
  # A record is just its name, so a page reads straight off the assertion. The fake finder
  # honours the real contract: it owns the probe bucket and reports the retained buckets' keys.
  let(:names) { %w[actionpack bootstrap classnames debug entityframework] }
  let(:dropped_records) { [] }
  let(:requests) { [] }

  let(:finder_class) do
    rows = names
    dropped = dropped_records
    log = requests

    Class.new do
      define_method(:initialize) do |source, params: {}|
        @source = source
        @params = params
      end

      define_method(:execute) do
        log << @params

        keys = rows.map { |name| { 'component_name' => name } }
        keys = keys.reverse if @params[:sort] == :desc

        after_key = @params[:after_key]
        keys = keys.drop_while { |key| key != after_key.to_h }.drop(1) if after_key

        page_size = @params[:per_page]
        kept = keys.first(page_size)

        Search::Elastic::CompositePagination::Page.new(
          records: kept.filter_map { |key| key['component_name'] unless dropped.include?(key['component_name']) },
          first_key: kept.first,
          last_key: kept.last,
          has_next_page: keys.size > page_size
        )
      end
    end
  end

  let(:source) { :a_group }

  def paginator(cursor: nil, per_page: 2, sort: 'asc', sort_by: 'name')
    described_class.new(
      finder: finder_class, source: source,
      params: { sort: sort, sort_by: sort_by }.with_indifferent_access,
      cursor: cursor, per_page: per_page
    )
  end

  describe '#initialize' do
    # The finder clamps to its own MAX_PAGE_SIZE.
    it 'passes the requested per_page through to the finder' do
      paginator(per_page: 5_000).records

      expect(requests.last[:per_page]).to eq(5_000)
    end
  end

  describe 'the first page' do
    subject(:page) { paginator }

    it 'asks the finder for the page and nothing else', :aggregate_failures do
      expect(page.records).to eq(%w[actionpack bootstrap])
      expect(requests.last).to include(after_key: nil, per_page: 2, sort: :asc)
    end

    it 'passes the caller params through to the finder' do
      paginator.records

      expect(requests.last).to include('sort_by' => 'name')
    end

    it 'has a next page but no previous page', :aggregate_failures do
      expect(page).to have_next_page
      expect(page).not_to have_previous_page
      expect(page.cursor_for_next_page).to be_present
      expect(page.cursor_for_previous_page).to be_nil
    end

    it 'is enumerable', :aggregate_failures do
      expect(page.to_a).to eq(%w[actionpack bootstrap])
      expect(page.size).to eq(2)
      expect(page).to be_any
      expect(page).not_to be_empty
    end
  end

  describe 'the last page' do
    subject(:page) do
      cursor = paginator.cursor_for_next_page
      cursor = paginator(cursor: cursor).cursor_for_next_page

      paginator(cursor: cursor)
    end

    it 'reports no next page', :aggregate_failures do
      expect(page.records).to eq(%w[entityframework])
      expect(page).not_to have_next_page
      expect(page.cursor_for_next_page).to be_nil
    end

    it 'still offers a previous page' do
      expect(page.cursor_for_previous_page).to be_present
    end
  end

  describe 'walking forward' do
    it 'visits every record exactly once' do
      expect(walk).to eq(names)
    end

    it 'visits every record exactly once when sorting descending' do
      expect(walk(sort: 'desc')).to eq(names.reverse)
    end

    def walk(**options)
      walked = []
      cursor = nil

      names.size.times do
        page = paginator(cursor: cursor, **options)
        walked.concat(page.records)
        cursor = page.cursor_for_next_page
        break if cursor.blank?
      end

      walked
    end
  end

  describe 'walking backward' do
    # From page 2 the flipped and unflipped constructions agree, so only page 3 catches a
    # missing source-order flip.
    it 'lands on the previous page rather than the first page' do
      page1 = paginator
      page2 = paginator(cursor: page1.cursor_for_next_page)
      page3 = paginator(cursor: page2.cursor_for_next_page)

      back = paginator(cursor: page3.cursor_for_previous_page)

      expect(back.records).to eq(page2.records)
      expect(back.records).not_to eq(page1.records)
    end

    it 'reverses the sort of the underlying request' do
      cursor = paginator.cursor_for_next_page
      requests.clear

      paginator(cursor: paginator(cursor: cursor).cursor_for_previous_page).records

      expect(requests.last[:sort]).to eq(:desc)
    end

    it 'returns records in display order' do
      cursor = paginator.cursor_for_next_page
      back = paginator(cursor: paginator(cursor: cursor).cursor_for_previous_page)

      expect(back.records).to eq(%w[actionpack bootstrap])
    end

    it 'reports a next page and no previous page once it reaches the start', :aggregate_failures do
      cursor = paginator.cursor_for_next_page
      back = paginator(cursor: paginator(cursor: cursor).cursor_for_previous_page)

      expect(back).to have_next_page
      expect(back).not_to have_previous_page
    end
  end

  describe 'when a bucket produces no record' do
    let(:dropped_records) { %w[actionpack] }

    it 'trusts the finder rather than the record count for has_next_page?', :aggregate_failures do
      page = paginator

      expect(page.records).to eq(%w[bootstrap])
      expect(page).to have_next_page
    end

    it 'does not pull the probe row onto the page' do
      expect(paginator.records).not_to include('classnames')
    end

    it 'still cuts the next cursor from the last retained bucket' do
      expect(paginator(cursor: paginator.cursor_for_next_page).records).to eq(%w[classnames debug])
    end
  end

  describe 'cursor validation' do
    it 'rejects a cursor that is not base64' do
      expect { paginator(cursor: 'not-a-cursor') }
        .to raise_error(described_class::InvalidCursorError, 'Invalid cursor')
    end

    it 'rejects a cursor with an unknown direction' do
      cursor = described_class::CURSOR_CONVERTER.dump(described_class::DIRECTION_KEY => 'x')

      expect { paginator(cursor: cursor) }
        .to raise_error(described_class::InvalidCursorError, /Invalid cursor direction/)
    end

    # Every backward cursor this class mints carries a key, so one without is malformed.
    it 'rejects a backward cursor that carries no after_key' do
      cursor = described_class::CURSOR_CONVERTER.dump(
        sort_by: 'name', sort: 'asc',
        described_class::DIRECTION_KEY => described_class::BACKWARD_DIRECTION
      )

      expect { paginator(cursor: cursor) }
        .to raise_error(described_class::InvalidCursorError, 'Invalid cursor after_key')
    end

    it 'rejects a cursor whose after_key is not a hash' do
      cursor = described_class::CURSOR_CONVERTER.dump(
        after_key: 'actionpack', sort_by: 'name', sort: 'asc',
        described_class::DIRECTION_KEY => described_class::FORWARD_DIRECTION
      )

      expect { paginator(cursor: cursor) }
        .to raise_error(described_class::InvalidCursorError, 'Invalid cursor after_key')
    end

    it 'rejects a cursor minted under a different sort direction' do
      cursor = paginator.cursor_for_next_page

      expect { paginator(cursor: cursor, sort: 'desc') }
        .to raise_error(described_class::InvalidCursorError, 'The cursor was created for a different ordering')
    end

    it 'rejects a cursor minted under a different sort field' do
      cursor = paginator.cursor_for_next_page

      expect { paginator(cursor: cursor, sort_by: 'severity') }
        .to raise_error(described_class::InvalidCursorError, 'The cursor was created for a different ordering')
    end
  end
end
