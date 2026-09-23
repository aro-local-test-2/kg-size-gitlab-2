# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sbom::OccurrenceRefsFilterable, feature_category: :dependency_management do
  using RSpec::Parameterized::TableSyntax

  let_it_be(:group) { create(:group) }
  let_it_be(:developer) { create(:user, developer_of: group) }
  let_it_be(:guest) { create(:user, guest_of: group) }

  let(:consumer_class) do
    filterable = described_class

    Class.new do
      include filterable

      attr_reader :current_user, :filterable_namespace

      def initialize(current_user, filterable_namespace)
        @current_user = current_user
        @filterable_namespace = filterable_namespace
      end

      public :use_elasticsearch?, :advanced_filters_requested?, :advanced_filters_available?,
        :validate_advanced_filters!
    end
  end

  let(:user) { developer }

  subject(:consumer) { consumer_class.new(user, group) }

  before do
    stub_licensed_features(dependency_scanning: true)
    allow(::Search::Elastic::SbomOccurrenceRefIndexHelper)
      .to receive(:advanced_dependency_management_allowed?).and_return(true)
  end

  describe '#advanced_filters_requested?' do
    it 'is true for malware in either state', :aggregate_failures do
      expect(consumer.advanced_filters_requested?(malware: true)).to be(true)
      expect(consumer.advanced_filters_requested?(malware: false)).to be(true)
    end

    it 'is true for the string a REST caller sends' do
      filters = ActionController::Parameters.new(malware: 'false').permit(:malware)

      expect(consumer.advanced_filters_requested?(filters)).to be(true)
    end

    it 'is false when no advanced filter was asked for', :aggregate_failures do
      expect(consumer.advanced_filters_requested?({})).to be(false)
      expect(consumer.advanced_filters_requested?(component_names: %w[actionpack])).to be(false)
    end
  end

  describe '#advanced_filters_available?' do
    where(:user, :feature_flag, :available) do
      ref(:developer) | true  | true
      ref(:developer) | false | false
      ref(:guest)     | true  | false
      nil             | true  | false
    end

    with_them do
      before do
        stub_feature_flags(malicious_packages_dependency_list_filtering: feature_flag)
      end

      it { expect(consumer.advanced_filters_available?).to be(available) }
    end

    # Readiness reaches the concern through the ability, not a direct call:
    # Sbom::AdvancedDependencyManagementPolicy prevents it when the index cannot serve reads.
    it 'is false when the Elasticsearch index is not ready for reads' do
      allow(::Search::Elastic::SbomOccurrenceRefIndexHelper)
        .to receive(:advanced_dependency_management_allowed?).and_return(false)

      expect(consumer.advanced_filters_available?).to be(false)
    end
  end

  describe '#validate_advanced_filters!' do
    it 'passes when no advanced filter was asked for', :aggregate_failures do
      expect { consumer.validate_advanced_filters!({}) }.not_to raise_error
      expect { consumer.validate_advanced_filters!(component_names: %w[actionpack]) }.not_to raise_error
    end

    it 'passes when the filter is available' do
      expect { consumer.validate_advanced_filters!(malware: true) }.not_to raise_error
    end

    context 'when the filter is unavailable' do
      before do
        stub_feature_flags(malicious_packages_dependency_list_filtering: false)
      end

      it 'raises rather than falling back to an unfiltered list', :aggregate_failures do
        [true, false].each do |value|
          expect { consumer.validate_advanced_filters!(malware: value) }
            .to raise_error(::Gitlab::Graphql::Errors::ArgumentError, 'The malware filter is not available.')
        end
      end

      it 'raises for a user without the ability' do
        consumer = consumer_class.new(guest, group)

        expect { consumer.validate_advanced_filters!(malware: true) }
          .to raise_error(::Gitlab::Graphql::Errors::ArgumentError)
      end
    end

    context 'when policy_violations is combined with an advanced filter' do
      let(:filters) { { malware: true, policy_violations: [:dismissed_in_mr] } }

      it 'raises rather than dropping one of the two filters' do
        expect { consumer.validate_advanced_filters!(filters) }.to raise_error(
          ::Gitlab::Graphql::Errors::ArgumentError,
          'The policy_violations filter cannot be combined with the malware filter.'
        )
      end

      # Whether the index can serve the request does not change that the pair is unanswerable,
      # so the caller gets the same error either way.
      it 'raises even when the advanced filter is unavailable' do
        stub_feature_flags(malicious_packages_dependency_list_filtering: false)

        expect { consumer.validate_advanced_filters!(filters) }.to raise_error(
          ::Gitlab::Graphql::Errors::ArgumentError,
          'The policy_violations filter cannot be combined with the malware filter.'
        )
      end

      it 'passes when no advanced filter accompanies it' do
        expect { consumer.validate_advanced_filters!(policy_violations: [:dismissed_in_mr]) }
          .not_to raise_error
      end
    end
  end

  describe '#use_elasticsearch?' do
    it 'is true only when an advanced filter was asked for and is available', :aggregate_failures do
      expect(consumer.use_elasticsearch?(malware: true)).to be(true)
      expect(consumer.use_elasticsearch?({})).to be(false)
    end

    it 'is false when the filter is unavailable' do
      stub_feature_flags(malicious_packages_dependency_list_filtering: false)

      expect(consumer.use_elasticsearch?(malware: true)).to be(false)
    end
  end

  describe '#filterable_namespace' do
    let(:incomplete_consumer_class) do
      filterable = described_class

      Class.new do
        include filterable

        def current_user; end

        public :advanced_filters_available?
      end
    end

    it 'tells an including class it has to supply one' do
      expect { incomplete_consumer_class.new.advanced_filters_available? }
        .to raise_error(NotImplementedError, /must implement #filterable_namespace/)
    end
  end
end
