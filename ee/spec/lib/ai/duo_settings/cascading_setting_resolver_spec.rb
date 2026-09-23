# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoSettings::CascadingSettingResolver, feature_category: :ai_abstraction_layer do
  describe '.enabled?' do
    let(:attribute) { :duo_auto_mode_enabled? }

    context 'when a project is given' do
      let_it_be_with_reload(:project) { create(:project) }

      it 'returns true when the project setting is enabled' do
        project.project_setting.update!(duo_auto_mode_enabled: true)

        expect(described_class.enabled?(project: project, namespace: nil, attribute: attribute)).to be(true)
      end

      it 'returns false when the project setting is disabled' do
        project.project_setting.update!(duo_auto_mode_enabled: false)

        expect(described_class.enabled?(project: project, namespace: nil, attribute: attribute)).to be(false)
      end

      it 'returns false when the project has no project_setting' do
        allow(project).to receive(:project_setting).and_return(nil)

        expect(described_class.enabled?(project: project, namespace: nil, attribute: attribute)).to be(false)
      end

      it 'prefers the project setting over the namespace setting' do
        project.project_setting.update!(duo_auto_mode_enabled: true)
        namespace = create(:group)
        namespace.namespace_settings.update!(duo_auto_mode_enabled: false)

        expect(described_class.enabled?(project: project, namespace: namespace, attribute: attribute)).to be(true)
      end
    end

    context 'when no project is given' do
      let_it_be_with_reload(:namespace) { create(:group) }

      it 'returns true when the namespace setting is enabled' do
        namespace.namespace_settings.update!(duo_auto_mode_enabled: true)

        expect(described_class.enabled?(project: nil, namespace: namespace, attribute: attribute)).to be(true)
      end

      it 'returns false when the namespace setting is disabled' do
        namespace.namespace_settings.update!(duo_auto_mode_enabled: false)

        expect(described_class.enabled?(project: nil, namespace: namespace, attribute: attribute)).to be(false)
      end

      it 'returns false when the namespace is nil' do
        expect(described_class.enabled?(project: nil, namespace: nil, attribute: attribute)).to be(false)
      end
    end
  end
end
