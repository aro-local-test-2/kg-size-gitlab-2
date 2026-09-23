# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::FlowSchedules::CronConverterService, feature_category: :code_suggestions do
  using RSpec::Parameterized::TableSyntax

  subject(:execute) { described_class.new(schedule_config).execute }

  describe '#execute' do
    context 'with a valid schedule config' do
      where(:config, :expected_cron) do
        { 'frequency' => 'EVERY_15_MINUTES' }                                        | '*/15 * * * *'
        { 'frequency' => 'EVERY_30_MINUTES' }                                        | '*/30 * * * *'
        { 'frequency' => 'HOURLY', 'minute' => 15 }                                  | '15 * * * *'
        { 'frequency' => 'HOURLY' }                                                  | '0 * * * *'
        { 'frequency' => 'DAILY', 'minute' => 30, 'hour' => 14 }                     | '30 14 * * *'
        { 'frequency' => 'DAILY' }                                                   | '0 0 * * *'
        { 'frequency' => 'WEEKDAYS', 'minute' => 5, 'hour' => 8 }                    | '5 8 * * 1-5'
        { 'frequency' => 'WEEKLY', 'minute' => 30, 'hour' => 14, 'dayOfWeek' => 3 }  | '30 14 * * 3'
        { 'frequency' => 'WEEKLY' }                                                  | '0 0 * * 0'
        { 'frequency' => 'MONTHLY', 'minute' => 0, 'hour' => 6, 'dayOfMonth' => 15 } | '0 6 15 * *'
        { 'frequency' => 'MONTHLY' }                                                 | '0 0 1 * *'
      end

      with_them do
        let(:schedule_config) { config }

        it 'converts to the expected cron with the default timezone' do
          expect(execute).to be_success
          expect(execute.payload).to eq(cron: expected_cron, cron_timezone: 'Etc/UTC')
        end
      end
    end

    context 'with a timezone' do
      let(:schedule_config) { { 'frequency' => 'DAILY', 'timezone' => 'America/New_York' } }

      it 'returns the given timezone' do
        expect(execute).to be_success
        expect(execute.payload[:cron_timezone]).to eq('America/New_York')
      end
    end

    context 'with symbol keys' do
      let(:schedule_config) { { frequency: 'HOURLY', minute: 15 } }

      it 'converts like string keys' do
        expect(execute).to be_success
        expect(execute.payload[:cron]).to eq('15 * * * *')
      end
    end

    context 'with an unknown frequency' do
      let(:schedule_config) { { 'frequency' => 'YEARLY' } }

      it 'returns an error listing the valid values' do
        expect(execute).to be_error
        expect(execute.message).to include('Unknown schedule frequency: YEARLY')
        expect(execute.message).to include('EVERY_15_MINUTES')
      end
    end

    context 'with a nil config' do
      let(:schedule_config) { nil }

      it 'returns an error' do
        expect(execute).to be_error
        expect(execute.message).to include('Unknown schedule frequency')
      end
    end

    context 'when the config produces an invalid cron expression' do
      let(:schedule_config) { { 'frequency' => 'HOURLY', 'minute' => 99 } }

      it 'returns an error' do
        expect(execute).to be_error
        expect(execute.message).to eq('Generated invalid cron expression: 99 * * * *')
      end
    end

    context 'with an invalid timezone' do
      let(:schedule_config) { { 'frequency' => 'DAILY', 'timezone' => 'Not/AZone' } }

      it 'returns an error' do
        expect(execute).to be_error
        expect(execute.message).to eq('Invalid timezone: Not/AZone')
      end
    end
  end
end
