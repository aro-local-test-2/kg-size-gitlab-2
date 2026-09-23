# frozen_string_literal: true

RSpec.shared_examples 'duo_auto_mode_availability setter' do
  describe '#duo_auto_mode_availability=' do
    using RSpec::Parameterized::TableSyntax

    where(:availability_value, :expected_enabled, :expected_lock) do
      "default_on"  | true  | false
      "default_off" | false | false
      "never_on"    | false | true
    end

    with_them do
      before do
        setting.duo_auto_mode_availability = availability_value
      end

      it 'sets the expected enabled and lock values' do
        expect(setting.duo_auto_mode_enabled).to eq expected_enabled
        expect(setting.lock_duo_auto_mode_enabled).to eq expected_lock
      end
    end

    it 'raises KeyError for invalid values' do
      expect { setting.duo_auto_mode_availability = "invalid" }
        .to raise_error(KeyError)
    end
  end
end

RSpec.shared_examples 'duo_auto_mode_availability getter' do
  describe '#duo_auto_mode_availability' do
    using RSpec::Parameterized::TableSyntax

    where(:enabled, :locked, :expected_availability) do
      true  | false | :default_on
      false | false | :default_off
      false | true  | :never_on
      true  | true  | :never_on
    end

    with_them do
      before do
        setting.duo_auto_mode_enabled = enabled
        setting.lock_duo_auto_mode_enabled = locked
      end

      it 'returns the expected availability' do
        expect(setting.duo_auto_mode_availability).to eq expected_availability
      end
    end
  end
end
