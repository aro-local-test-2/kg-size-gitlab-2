# frozen_string_literal: true

require 'spec_helper'
require File.expand_path('ee/active_context/migrate/20260918000000_set_dev_queue_shard_count.rb')

RSpec.describe SetDevQueueShardCount, feature_category: :global_search do
  let(:version) { 20260918000000 }
  let(:migration_class) { ::ActiveContext::Migration::Dictionary.instance.find_by_version(version) }
  let_it_be(:collection) { create(:ai_active_context_collection, :code_collection) }

  subject(:migrate) { migration_class.new.migrate! }

  it 'sets queue_shard_count on the collection' do
    expect { migrate }.to change { collection.reload.queue_shard_count }.from(nil).to(4)
  end

  context 'when queue_shard_count is already 4' do
    before do
      collection.update_columns(options: collection.options.merge('queue_shard_count' => 4))
    end

    it 'does not change the options' do
      expect { migrate }.not_to change { collection.reload.options }
    end
  end

  describe '#skip?' do
    subject(:skip) { migration_class.new.skip? }

    it { is_expected.to be(true) }

    context 'when in the development environment' do
      before do
        stub_rails_env('development')
      end

      it { is_expected.to be(false) }
    end
  end
end
