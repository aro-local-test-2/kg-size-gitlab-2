# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ci::Minutes::NamespaceMonthlyUsage, feature_category: :hosted_runners do
  let_it_be_with_refind(:namespace) do
    create(:namespace,
      shared_runners_minutes_limit: 1_000,
      extra_shared_runners_minutes_limit: 500)
  end

  let_it_be_with_refind(:current_usage) do
    create(:ci_namespace_monthly_usage,
      :with_warning_notification_level,
      namespace: namespace,
      amount_used: 100)
  end

  describe 'validations' do
    it 'validates shard number' do
      is_expected.to validate_numericality_of(:shard_number)
                       .is_greater_than_or_equal_to(1)
                       .is_less_than_or_equal_to(described_class::MAX_NUMBER_OF_SHARDS)
    end

    it { is_expected.to validate_uniqueness_of(:shard_number).scoped_to([:namespace_id, :date]) }
  end

  describe 'unique index' do
    it 'raises unique index violation' do
      expect { create(:ci_namespace_monthly_usage, namespace: namespace) }
        .to raise_error { ActiveRecord::RecordNotUnique }
    end

    it 'does not raise exception if unique index is not violated' do
      expect do
        create(:ci_namespace_monthly_usage, namespace: namespace, date: described_class.beginning_of_month(1.month.ago))
      end
        .to change { described_class.count }.by(1)
    end
  end

  describe '.find_or_create_current' do
    subject { described_class.find_or_create_current(namespace_id: namespace.id) }

    context 'when the database is read-only' do
      before do
        current_usage.destroy!
        allow(::Gitlab::Database).to receive(:read_only?).and_return(true)
      end

      it 'returns a new unsaved record without persisting it' do
        expect { subject }.not_to change { described_class.count }

        expect(subject).not_to be_persisted
        expect(subject.namespace_id).to eq(namespace.id)
        expect(subject.shard_number).to eq(described_class::FIRST_SHARD_NUMBER)
      end
    end

    shared_examples 'creates usage record' do
      it 'creates new record and resets minutes consumption', :freeze_time do
        expect { subject }.to change { described_class.count }.by(1)

        expect(subject.amount_used).to eq(0)
        expect(subject.namespace).to eq(namespace)
        expect(subject.date).to eq(described_class.beginning_of_month)
        expect(subject.shard_number).to eq(described_class::FIRST_SHARD_NUMBER)
        expect(subject.notification_level).to eq(::Ci::Minutes::Notification::PERCENTAGES.fetch(:not_set))
        expect(subject.created_at).to eq(Time.current)
      end

      it 'kicks off Ci::Minutes::RefreshCachedDataWorker' do
        expect(::Ci::Minutes::RefreshCachedDataWorker)
          .to receive(:perform_async)
          .with(namespace.id)

        subject
      end
    end

    shared_examples 'does not update the additional minutes' do
      it 'does not update the additional minutes' do
        expect { subject }
          .not_to change { namespace.reload.extra_shared_runners_minutes_limit }
      end
    end

    shared_examples 'attempts recalculation of additional minutes' do
      context 'when namespace has any additional minutes' do
        context 'when last known amount_used is greater than the monthly limit' do
          before do
            previous_usage.update!(amount_used: 1_200)
          end

          it 'recalculates the remaining additional minutes' do
            expect { subject }
              .to change { namespace.reload.extra_shared_runners_minutes_limit }
              .from(500).to(300)
          end

          context 'when last known amount_used is greater than the total limit' do
            before do
              previous_usage.update!(amount_used: 2_000)
            end

            it 'recalculates the remaining additional minutes' do
              expect { subject }
                .to change { namespace.reload.extra_shared_runners_minutes_limit }
                .from(500).to(0)
            end
          end

          context 'when limit is disabled' do
            before do
              namespace.update!(
                shared_runners_minutes_limit: 0,
                extra_shared_runners_minutes_limit: 0)
            end

            it_behaves_like 'does not update the additional minutes'
          end
        end

        context 'when amount_used is lower than the monthly limit' do
          before do
            previous_usage.update!(amount_used: 900)
          end

          it_behaves_like 'does not update the additional minutes'
        end
      end

      context 'when namespace does not have additional minutes' do
        before do
          namespace.update!(extra_shared_runners_minutes_limit: 0)
        end

        it_behaves_like 'does not update the additional minutes'
      end
    end

    context 'when namespace usage does not exist for current month' do
      before do
        current_usage.destroy!
      end

      it_behaves_like 'creates usage record'
      it_behaves_like 'does not update the additional minutes'

      context 'when namespace usage exists for previous month' do
        let_it_be_with_reload(:previous_usage) do
          create(:ci_namespace_monthly_usage,
            namespace: namespace,
            date: described_class.beginning_of_month(1.month.ago))
        end

        it_behaves_like 'creates usage record'
        it_behaves_like 'attempts recalculation of additional minutes'
      end

      context 'when inside a transaction in ci database' do
        let_it_be_with_reload(:previous_usage) do
          create(:ci_namespace_monthly_usage,
            namespace: namespace,
            date: described_class.beginning_of_month(3.months.ago))
        end

        let_it_be(:project) { create(:project, namespace: namespace) }
        let_it_be_with_reload(:pipeline) { create(:ci_pipeline, project: project) }
        let_it_be_with_reload(:build) { create(:ci_build, :created, pipeline: pipeline) }

        before do
          namespace.clear_memoization(:ci_minutes_usage)
          create(:ci_runner, :instance_type)
        end

        subject do
          pipeline.transaction do
            pipeline.touch
            described_class.find_or_create_current(namespace_id: namespace.id)
          end
        end

        it_behaves_like 'creates usage record'
        it_behaves_like 'attempts recalculation of additional minutes'
      end

      context 'when last known usage is more than 1 month ago' do
        let_it_be_with_reload(:previous_usage) do
          create(:ci_namespace_monthly_usage,
            namespace: namespace,
            date: described_class.beginning_of_month(3.months.ago))
        end

        it_behaves_like 'creates usage record'
        it_behaves_like 'attempts recalculation of additional minutes'
      end

      context 'when namespace usage exists for previous months' do
        let_it_be_with_reload(:previous_usage) do
          create(:ci_namespace_monthly_usage,
            namespace: namespace,
            date: described_class.beginning_of_month(1.month.ago))
        end

        let_it_be(:old_usage) do
          create(:ci_namespace_monthly_usage,
            namespace: namespace,
            date: described_class.beginning_of_month(2.months.ago),
            amount_used: 2_000)
        end

        it_behaves_like 'creates usage record'
        it_behaves_like 'attempts recalculation of additional minutes'
      end

      context 'when a usage for another namespace exists for the current month' do
        let_it_be(:usage) { create(:ci_namespace_monthly_usage) }

        it_behaves_like 'creates usage record'
        it_behaves_like 'does not update the additional minutes'
      end
    end

    context 'when namespace usage exists for the current month' do
      it 'returns the existing usage', :freeze_time do
        expect(subject).to eq(current_usage)
      end

      it_behaves_like 'does not update the additional minutes'
    end

    context 'when several shards exist for the current month' do
      let_it_be(:other_shard) do
        create(:ci_namespace_monthly_usage, namespace: namespace, shard_number: 2)
      end

      it 'returns the first shard rather than an arbitrary one' do
        expect { subject }.not_to change { described_class.count }

        expect(subject).to eq(current_usage)
        expect(subject.shard_number).to eq(described_class::FIRST_SHARD_NUMBER)
      end
    end

    context 'when only a different shard exists for the current month' do
      let_it_be_with_reload(:previous_usage) do
        create(:ci_namespace_monthly_usage,
          namespace: namespace,
          date: described_class.beginning_of_month(1.month.ago),
          amount_used: 1_200)
      end

      before do
        current_usage.update!(shard_number: 2)
      end

      it 'creates and returns the first shard' do
        expect { subject }.to change { described_class.count }.by(1)

        expect(subject.shard_number).to eq(described_class::FIRST_SHARD_NUMBER)
      end

      # The month is already under way, so the backfilled first shard must not
      # recalculate a second time.
      it 'does not kick off Ci::Minutes::RefreshCachedDataWorker' do
        expect(::Ci::Minutes::RefreshCachedDataWorker).not_to receive(:perform_async)

        subject
      end

      it_behaves_like 'does not update the additional minutes'
    end
  end

  describe '.find_or_create_current_shard' do
    let(:build_id) { 10 }
    let(:shard_number) { described_class.generate_shard_number(build_id) }

    subject { described_class.find_or_create_current_shard(namespace_id: namespace.id, build_id: build_id) }

    shared_examples 'does not update the additional minutes' do
      it 'does not update the additional minutes' do
        expect { subject }
          .not_to change { namespace.reload.extra_shared_runners_minutes_limit }
      end
    end

    shared_examples 'does not kick off RefreshCachedData worker' do
      it 'does not kick off Ci::Minutes::RefreshCachedDataWorker' do
        expect(::Ci::Minutes::RefreshCachedDataWorker).not_to receive(:perform_async)

        subject
      end
    end

    context 'when build_id is nil' do
      let(:build_id) { nil }

      it 'raises an ArgumentError instead of resolving a shard' do
        expect { subject }.to raise_error(ArgumentError, 'build_id is required to select a shard')
      end
    end

    context 'when the database is read-only' do
      before do
        current_usage.destroy!
        allow(::Gitlab::Database).to receive(:read_only?).and_return(true)
      end

      it 'returns a new unsaved record on the resolved shard without persisting it' do
        expect { subject }.not_to change { described_class.count }

        expect(subject).not_to be_persisted
        expect(subject.namespace_id).to eq(namespace.id)
        expect(subject.shard_number).to eq(shard_number)
      end
    end

    context 'when the unique index rejects the insert' do
      let!(:conflicting_shard) do
        create(:ci_namespace_monthly_usage, namespace: namespace, shard_number: shard_number, amount_used: 50)
      end

      before do
        # A committed duplicate is normally caught by the uniqueness validation first, so
        # the validation is skipped here to reach the index branch that a race still hits.
        allow_next_instance_of(described_class) do |usage|
          allow(usage).to receive(:valid?).and_return(true)
        end

        # Only the first read misses, which is what lets the insert reach the index.
        reads = 0
        allow(described_class).to receive(:unsafe_find_current_shard).and_wrap_original do |original, *args|
          reads += 1
          reads == 1 ? nil : original.call(*args)
        end
      end

      it 'returns the existing shard without creating a new record' do
        expect { subject }.not_to change { described_class.count }

        expect(subject).to eq(conflicting_shard)
      end

      it_behaves_like 'does not kick off RefreshCachedData worker'
      it_behaves_like 'does not update the additional minutes'
    end

    context 'when a concurrent write creates the first shard before this one lands' do
      let(:racing_build_id) { 5 }
      let(:racing_shard_number) { described_class.generate_shard_number(racing_build_id) }

      let_it_be_with_reload(:previous_usage) do
        create(:ci_namespace_monthly_usage,
          namespace: namespace,
          date: described_class.beginning_of_month(1.month.ago),
          amount_used: 1_200)
      end

      before do
        current_usage.destroy!

        # Reproduces the reported interleaving: the racing write commits the first shard
        # after this call decides that it starts the month, but before its own insert.
        raced = false
        allow(described_class).to receive(:create_or_find_shard).and_wrap_original do |original, *args, &block|
          if !raced && args.last == described_class::FIRST_SHARD_NUMBER
            raced = true
            described_class.find_or_create_current_shard(namespace_id: namespace.id, build_id: racing_build_id)
          end

          original.call(*args, &block)
        end
      end

      it 'recalculates the remaining additional minutes only once' do
        expect { subject }
          .to change { namespace.reload.extra_shared_runners_minutes_limit }
          .from(500).to(300)
      end

      it 'keeps a single first shard and creates both resolved shards' do
        subject

        expect(described_class.all_current_usages(namespace.id).pluck(:shard_number))
          .to contain_exactly(described_class::FIRST_SHARD_NUMBER, shard_number, racing_shard_number)
      end

      it 'kicks off Ci::Minutes::RefreshCachedDataWorker once' do
        expect(::Ci::Minutes::RefreshCachedDataWorker)
          .to receive(:perform_async)
          .with(namespace.id)
          .once

        subject
      end
    end

    context 'when no usage exists for the current month' do
      before do
        current_usage.destroy!
      end

      it 'creates the first shard alongside the resolved shard' do
        expect { subject }.to change { described_class.count }.by(2)

        expect(described_class.all_current_usages(namespace.id).pluck(:shard_number))
          .to contain_exactly(described_class::FIRST_SHARD_NUMBER, shard_number)
      end

      it 'returns a record on the resolved shard with consumption reset', :freeze_time do
        expect(subject.amount_used).to eq(0)
        expect(subject.namespace).to eq(namespace)
        expect(subject.date).to eq(described_class.beginning_of_month)
        expect(subject.shard_number).to eq(shard_number)
        expect(subject.notification_level).to eq(::Ci::Minutes::Notification::PERCENTAGES.fetch(:not_set))
        expect(subject.created_at).to eq(Time.current)
      end

      it 'kicks off Ci::Minutes::RefreshCachedDataWorker' do
        expect(::Ci::Minutes::RefreshCachedDataWorker)
          .to receive(:perform_async)
          .with(namespace.id)

        subject
      end

      it_behaves_like 'does not update the additional minutes'

      context 'when usage exists for the previous month' do
        let_it_be_with_reload(:previous_usage) do
          create(:ci_namespace_monthly_usage,
            namespace: namespace,
            date: described_class.beginning_of_month(1.month.ago))
        end

        context 'when last known amount_used exceeds the monthly limit' do
          before do
            previous_usage.update!(amount_used: 1_200)
          end

          it 'recalculates the remaining additional minutes' do
            expect { subject }
              .to change { namespace.reload.extra_shared_runners_minutes_limit }
              .from(500).to(300)
          end
        end

        context 'when last known amount_used is below the monthly limit' do
          before do
            previous_usage.update!(amount_used: 900)
          end

          it_behaves_like 'does not update the additional minutes'
        end
      end
    end

    context 'when the resolved shard already exists for the current month' do
      before do
        current_usage.update!(shard_number: shard_number)
      end

      it 'returns the existing shard without creating a new record', :freeze_time do
        expect { subject }.not_to change { described_class.count }

        expect(subject).to eq(current_usage)
      end

      it_behaves_like 'does not kick off RefreshCachedData worker'
      it_behaves_like 'does not update the additional minutes'
    end

    context 'when the first shard already exists for the current month' do
      let_it_be_with_reload(:previous_usage) do
        create(:ci_namespace_monthly_usage,
          namespace: namespace,
          date: described_class.beginning_of_month(1.month.ago),
          amount_used: 1_200)
      end

      it 'creates the resolved shard as an additional row' do
        expect { subject }.to change { described_class.count }.by(1)

        expect(subject.shard_number).to eq(shard_number)
        expect(described_class.all_current_usages(namespace.id).pluck(:shard_number))
          .to contain_exactly(described_class::FIRST_SHARD_NUMBER, shard_number)
      end

      # The month was recalculated when the first shard was created.
      it_behaves_like 'does not kick off RefreshCachedData worker'
      it_behaves_like 'does not update the additional minutes'
    end

    context 'when only a different shard exists for the current month' do
      let(:existing_shard_number) do
        shard_number == described_class::MAX_NUMBER_OF_SHARDS ? shard_number - 1 : shard_number + 1
      end

      before do
        current_usage.update!(shard_number: existing_shard_number)
      end

      it 'creates the resolved shard and backfills the first shard' do
        expect { subject }.to change { described_class.count }.by(2)

        expect(subject.shard_number).to eq(shard_number)
        expect(described_class.all_current_usages(namespace.id).pluck(:shard_number))
          .to contain_exactly(described_class::FIRST_SHARD_NUMBER, existing_shard_number, shard_number)
      end

      # The month is already under way, so the backfilled first shard must not
      # recalculate a second time.
      it_behaves_like 'does not kick off RefreshCachedData worker'
    end
  end

  describe '.generate_shard_number' do
    it 'maps a build_id to a shard within the valid range' do
      expect(described_class.generate_shard_number(12345))
        .to be_between(1, described_class::MAX_NUMBER_OF_SHARDS)
    end

    it 'is deterministic for the same build_id' do
      first_result = described_class.generate_shard_number(999)

      expect(described_class.generate_shard_number(999)).to eq(first_result)
    end

    it 'maps build_id 424242 to the expected shard' do
      expect(described_class.generate_shard_number(424242)).to eq(2)
    end
  end

  describe '.for_shard' do
    it 'returns usages for the given shard number' do
      other_shard = create(:ci_namespace_monthly_usage, namespace: namespace, shard_number: 2)

      expect(described_class.for_namespace(namespace).for_shard(1)).to contain_exactly(current_usage)
      expect(described_class.for_namespace(namespace).for_shard(2)).to contain_exactly(other_shard)
    end
  end

  describe '.all_current_usages' do
    subject { described_class.all_current_usages(namespace.id) }

    it 'returns usages for the given namespace in the current month' do
      expect(subject).to contain_exactly(current_usage)
    end

    context 'when there are usages from previous months' do
      before do
        create(:ci_namespace_monthly_usage,
          namespace: namespace,
          amount_used: 999,
          date: described_class.beginning_of_month(1.month.ago))
      end

      it 'excludes previous month usages' do
        expect(subject).to contain_exactly(current_usage)
      end
    end

    context 'when there are usages for other namespaces' do
      before do
        create(:ci_namespace_monthly_usage, amount_used: 999)
      end

      it 'excludes other namespaces' do
        expect(subject).to contain_exactly(current_usage)
      end
    end

    context 'when there are multiple shards for the current month' do
      let_it_be(:second_shard) do
        create(:ci_namespace_monthly_usage, namespace: namespace, shard_number: 2)
      end

      it 'returns all shards' do
        expect(subject).to contain_exactly(current_usage, second_shard)
      end
    end

    context 'when there are no usages for the current month' do
      before do
        current_usage.destroy!
      end

      it 'returns an empty relation' do
        expect(subject).to be_empty
      end
    end
  end

  describe '.total_current_minutes_used' do
    subject { described_class.total_current_minutes_used(namespace.id) }

    context 'when there are no usages for the current month' do
      before do
        current_usage.destroy!
      end

      it { is_expected.to eq(0) }
    end

    context 'when there is a single usage record for the current month' do
      it 'returns the amount used as an integer' do
        expect(subject).to eq(100)
        expect(subject).to be_a(Integer)
      end
    end

    context 'when there are multiple shards for the current month' do
      before do
        create(:ci_namespace_monthly_usage, namespace: namespace, amount_used: 50, shard_number: 2)
      end

      it 'returns the sum of all shards' do
        expect(subject).to eq(150)
      end
    end

    context 'when there are usages from previous months' do
      before do
        create(:ci_namespace_monthly_usage,
          namespace: namespace,
          amount_used: 999,
          date: described_class.beginning_of_month(1.month.ago))
      end

      it 'only includes the current month' do
        expect(subject).to eq(100)
      end
    end

    context 'when there are usages for other namespaces' do
      before do
        create(:ci_namespace_monthly_usage, amount_used: 999)
      end

      it 'only includes the given namespace' do
        expect(subject).to eq(100)
      end
    end
  end

  describe '.aggregated_by_month' do
    let_it_be(:previous_month) { described_class.beginning_of_month(1.month.ago).to_date }

    subject(:aggregated) { described_class.aggregated_by_month(namespace) }

    it 'returns the shard values unchanged when a month holds a single shard' do
      expect(aggregated.size).to eq(1)
      expect(aggregated.first.date).to eq(described_class.beginning_of_month.to_date)
      expect(aggregated.first.amount_used).to eq(100)
    end

    it 'adds the shard values together for a month' do
      create(:ci_namespace_monthly_usage,
        namespace: namespace, shard_number: 2, amount_used: 50, shared_runners_duration: 30)

      expect(aggregated.size).to eq(1)
      expect(aggregated.first.amount_used).to eq(150)
      expect(aggregated.first.shared_runners_duration).to eq(30)
    end

    it 'returns one record for each month, most recent first' do
      create(:ci_namespace_monthly_usage, namespace: namespace, date: previous_month, amount_used: 20)
      create(:ci_namespace_monthly_usage,
        namespace: namespace, date: previous_month, shard_number: 2, amount_used: 5)

      expect(aggregated.map(&:date)).to eq([described_class.beginning_of_month.to_date, previous_month])
      expect(aggregated.map(&:amount_used)).to eq([100, 25])
    end

    it 'excludes other namespaces' do
      create(:ci_namespace_monthly_usage, amount_used: 999)

      expect(aggregated.map(&:amount_used)).to eq([100])
    end

    it 'returns readonly records that are not persisted and that carry the namespace' do
      usage = aggregated.first

      expect(usage).not_to be_persisted
      expect(usage.namespace).to eq(namespace)
      expect { usage.save!(validate: false) }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end

    context 'when a date is given' do
      subject(:aggregated) { described_class.aggregated_by_month(namespace, date: previous_month) }

      it 'returns that month only' do
        create(:ci_namespace_monthly_usage, namespace: namespace, date: previous_month, amount_used: 20)

        expect(aggregated.map(&:date)).to eq([previous_month])
        expect(aggregated.first.amount_used).to eq(20)
      end
    end

    context 'when the namespace is nil' do
      it 'returns an empty array without querying' do
        expect(described_class).not_to receive(:for_namespace)

        expect(described_class.aggregated_by_month(nil)).to eq([])
      end
    end
  end

  describe '#increase_usage' do
    it_behaves_like 'compute minutes increase usage'
  end

  describe '.for_namespace' do
    it 'returns usages for the namespace' do
      create(:ci_namespace_monthly_usage, namespace: create(:namespace))

      usages = described_class.for_namespace(namespace)

      expect(usages).to contain_exactly(current_usage)
    end
  end

  describe '.all_previous_usages', :freeze_time do
    let(:current_month) { described_class.beginning_of_month }

    subject { described_class.all_previous_usages(namespace) }

    context 'when there are no usage records' do
      it { is_expected.to be_empty }
    end

    context 'when there are usage records for the previous month' do
      let_it_be(:previous_month_usage_0) do
        create(:ci_namespace_monthly_usage, namespace: namespace, amount_used: 200,
          date: described_class.beginning_of_month - 2.months)
      end

      let_it_be(:previous_month_usage_1) do
        create(:ci_namespace_monthly_usage, namespace: namespace, amount_used: 200,
          date: described_class.beginning_of_month - 2.months, shard_number: 2)
      end

      let_it_be(:other_namespace_usage) do
        create(:ci_namespace_monthly_usage, amount_used: 200, date: described_class.beginning_of_month - 2.months)
      end

      let_it_be(:very_old_usage) do
        create(:ci_namespace_monthly_usage, namespace: namespace, amount_used: 300,
          date: described_class.beginning_of_month - 3.months)
      end

      it { is_expected.to contain_exactly(previous_month_usage_0, previous_month_usage_1) }
    end

    context 'when there are usage records older than the previous month' do
      let_it_be(:old_usage_1) do
        create(:ci_namespace_monthly_usage, namespace: namespace, amount_used: 300,
          date: described_class.beginning_of_month - 3.months)
      end

      let_it_be(:old_usage_2) do
        create(:ci_namespace_monthly_usage, namespace: namespace, amount_used: 300,
          date: described_class.beginning_of_month - 3.months, shard_number: 2)
      end

      let_it_be(:other_namespace_usage) do
        create(:ci_namespace_monthly_usage, amount_used: 200, date: described_class.beginning_of_month - 3.months)
      end

      let_it_be(:very_old_usage) do
        create(:ci_namespace_monthly_usage, namespace: namespace, amount_used: 300,
          date: described_class.beginning_of_month - 4.months)
      end

      it { is_expected.to contain_exactly(old_usage_1, old_usage_2) }
    end
  end

  describe '.reset_current_usage', :aggregate_failures do
    subject { described_class.reset_current_usage(namespace) }

    it 'resets current usage and notification level' do
      subject

      current_usage.reload
      expect(current_usage.amount_used).to eq(0)
      expect(current_usage.notification_level).to eq(Ci::Minutes::Notification::PERCENTAGES.fetch(:not_set))
    end

    it 'does not reset data from previous months' do
      previous_usage = create(:ci_namespace_monthly_usage,
        :with_warning_notification_level,
        namespace: namespace,
        date: 1.month.ago.beginning_of_month.to_date)

      subject

      previous_usage.reload
      expect(previous_usage.amount_used).to eq(100)
      expect(previous_usage.notification_level).to eq(Ci::Minutes::Notification::PERCENTAGES.fetch(:warning))
    end

    it 'does not reset data from other namespaces' do
      another_usage = create(:ci_namespace_monthly_usage, :with_warning_notification_level)

      subject

      another_usage.reload
      expect(another_usage.amount_used).to eq(100)
      expect(another_usage.notification_level).to eq(Ci::Minutes::Notification::PERCENTAGES.fetch(:warning))
    end
  end

  describe '.reset_current_notification_level' do
    subject { described_class.reset_current_notification_level(namespace) }

    it 'resets current notification level' do
      expect { subject }
        .to change { current_usage.reload.notification_level }
        .to(Ci::Minutes::Notification::PERCENTAGES.fetch(:not_set))
    end

    it 'does not reset notification level from previous months' do
      previous_usage = create(:ci_namespace_monthly_usage,
        :with_warning_notification_level,
        namespace: namespace,
        date: 1.month.ago.beginning_of_month.to_date)

      expect { subject }
        .not_to change { previous_usage.reload.notification_level }
    end

    it 'does not reset notification level from other namespaces' do
      another_usage = create(:ci_namespace_monthly_usage, :with_warning_notification_level)

      expect { subject }
        .not_to change { another_usage.reload.notification_level }
    end
  end

  describe '.any_usage_notified?' do
    subject { described_class.any_usage_notified?(namespace.id, remaining_percentage) }

    let(:remaining_percentage) { Ci::Minutes::Notification::PERCENTAGES.fetch(:warning) }

    context 'when no shard has the given notification level' do
      before do
        current_usage.update!(notification_level: Ci::Minutes::Notification::PERCENTAGES.fetch(:not_set))
      end

      it { is_expected.to be false }
    end

    context 'when one shard has the given notification level' do
      before do
        current_usage.update!(notification_level: remaining_percentage)
      end

      it { is_expected.to be true }
    end

    context 'when multiple shards exist and one matches' do
      let!(:other_shard) do
        create(:ci_namespace_monthly_usage,
          namespace: namespace,
          notification_level: Ci::Minutes::Notification::PERCENTAGES.fetch(:not_set),
          shard_number: current_usage.shard_number + 1)
      end

      before do
        current_usage.update!(notification_level: remaining_percentage)
      end

      it { is_expected.to be true }
    end

    context 'when multiple shards exist and none match' do
      let!(:other_shard) do
        create(:ci_namespace_monthly_usage,
          namespace: namespace,
          notification_level: Ci::Minutes::Notification::PERCENTAGES.fetch(:not_set),
          shard_number: current_usage.shard_number + 1)
      end

      before do
        current_usage.update!(notification_level: Ci::Minutes::Notification::PERCENTAGES.fetch(:not_set))
      end

      it { is_expected.to be false }
    end

    context 'when usages exist for another namespace' do
      let!(:other_usage) do
        create(:ci_namespace_monthly_usage, notification_level: remaining_percentage)
      end

      before do
        current_usage.update!(notification_level: Ci::Minutes::Notification::PERCENTAGES.fetch(:not_set))
      end

      it { is_expected.to be false }
    end

    context 'when usages exist for a previous month', :freeze_time do
      let!(:previous_usage) do
        create(:ci_namespace_monthly_usage,
          namespace: namespace,
          notification_level: remaining_percentage,
          date: 1.month.ago.beginning_of_month.to_date)
      end

      before do
        current_usage.update!(notification_level: Ci::Minutes::Notification::PERCENTAGES.fetch(:not_set))
      end

      it { is_expected.to be false }
    end
  end

  describe '.any_total_usage_notified?' do
    subject { described_class.any_total_usage_notified?(namespace.id) }

    context 'when a shard has exceeded notification level' do
      before do
        current_usage.update!(notification_level: Ci::Minutes::Notification::PERCENTAGES.fetch(:exceeded))
      end

      it { is_expected.to be true }
    end

    context 'when a shard has warning but not exceeded notification level' do
      before do
        current_usage.update!(notification_level: Ci::Minutes::Notification::PERCENTAGES.fetch(:warning))
      end

      it { is_expected.to be false }
    end
  end

  describe 'scope: .by_namespace_and_date', :freeze_time do
    let_it_be(:date) { Date.today.beginning_of_month }
    let_it_be(:namespace) { create(:namespace) }
    let_it_be(:ci_usage) { create(:ci_namespace_monthly_usage, namespace: namespace, amount_used: 200, date: date) }
    let_it_be(:other_namespace) { create(:namespace) }

    context 'when there are matching records' do
      it 'returns the matching records' do
        expect(described_class.by_namespace_and_date(namespace, date)).to eq([ci_usage])
      end
    end

    context 'when there are no matching records' do
      it 'returns an empty array' do
        expect(described_class.by_namespace_and_date(other_namespace, date)).to eq([])
      end
    end
  end
end
