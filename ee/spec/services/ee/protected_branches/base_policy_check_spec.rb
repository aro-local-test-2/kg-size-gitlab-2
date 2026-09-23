# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EE::ProtectedBranches::BasePolicyCheck, feature_category: :security_policy_management do
  describe '#violated?' do
    it 'raises for the abstract base class' do
      expect { described_class.new(nil, nil).violated? }.to raise_error(NotImplementedError)
    end
  end

  describe 'PolicyViolationError' do
    it 'is a subclass of AccessDeniedError so existing rescue handlers keep working' do
      expect(described_class::PolicyViolationError.ancestors).to include(::Gitlab::Access::AccessDeniedError)
    end
  end

  describe '.check!' do
    let(:check_class) do
      Class.new(described_class) do
        def initialize(violated:)
          @violated = violated
          super(nil, nil)
        end

        def violated?
          @violated
        end

        private

        def violation_message
          'blocked by a test policy'
        end
      end
    end

    context 'when the check is violated' do
      it 'raises PolicyViolationError with the violation message' do
        expect { check_class.new(violated: true).check! }
          .to raise_error(described_class::PolicyViolationError, 'blocked by a test policy')
      end
    end

    context 'when the check is not violated' do
      it 'does not raise' do
        expect { check_class.new(violated: false).check! }.not_to raise_error
      end
    end
  end

  describe '#policies_enforceable?' do
    let_it_be_with_reload(:root_group) { create(:group) }
    let_it_be(:project) { create(:project, group: root_group) }

    let(:check_class) do
      Class.new(described_class) do
        def enforceable?(container)
          policies_enforceable?(container)
        end
      end
    end

    let(:container) { project }

    subject(:enforceable) { check_class.new(nil, nil).enforceable?(container) }

    context 'when security_orchestration_policies is licensed' do
      before do
        stub_licensed_features(security_orchestration_policies: true)
      end

      it { is_expected.to be(true) }
    end

    context 'when nothing is licensed' do
      before do
        stub_licensed_features(security_orchestration_policies: false, dependency_firewall: false)
      end

      it { is_expected.to be(false) }
    end

    context 'when the dependency firewall is enforced without the security_orchestration_policies licence' do
      include_context 'with dependency firewall enforced without security_orchestration_policies licence'

      it 'keeps the gate closed because the check asks for security_orchestration_policies only' do
        expect(::Security::PolicyAvailability.any_available?(project)).to be(true)
        expect(enforceable).to be(false)
      end
    end

    context 'when the container is nil' do
      let(:container) { nil }

      before do
        stub_licensed_features(security_orchestration_policies: true)
      end

      it { is_expected.to be(false) }
    end
  end
end
