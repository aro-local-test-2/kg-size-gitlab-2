# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DependencyManagement::Remediation, feature_category: :dependency_management do
  let_it_be(:project) { create(:project) }

  subject(:remediation) { build(:dependency_management_remediation, project: project) }

  it { is_expected.to be_valid }

  describe 'associations' do
    it { is_expected.to belong_to(:project).required }
    it { is_expected.to belong_to(:merge_request).optional }
  end

  describe 'enums' do
    it { is_expected.to define_enum_for(:purl_type).with_values(::Enums::Sbom.purl_types) }
    it { is_expected.to define_enum_for(:state).with_values(described_class::STATES) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:purl_type) }
    it { is_expected.to validate_presence_of(:state) }
    it { is_expected.to validate_presence_of(:package_name) }
    it { is_expected.to validate_length_of(:package_name).is_at_most(255) }
    it { is_expected.to validate_presence_of(:current_version) }
    it { is_expected.to validate_length_of(:current_version).is_at_most(255) }
    it { is_expected.to validate_presence_of(:target_version) }
    it { is_expected.to validate_length_of(:target_version).is_at_most(255) }
    it { is_expected.to validate_length_of(:input_file_path).is_at_most(1024) }

    it 'accepts a blank input_file_path for a root manifest' do
      remediation.input_file_path = ''

      expect(remediation).to be_valid
    end

    it 'rejects a nil input_file_path' do
      remediation.input_file_path = nil

      expect(remediation).not_to be_valid
    end
  end

  describe 'uniqueness of the dependency location' do
    let(:attributes) do
      { project: project, purl_type: :npm, package_name: 'lodash', input_file_path: 'package.json' }
    end

    before do
      create(:dependency_management_remediation, **attributes)
    end

    it 'rejects a second row for the same location' do
      expect { create(:dependency_management_remediation, **attributes) }
        .to raise_error(ActiveRecord::RecordInvalid)
    end

    # The validation races, so the index is what actually enforces this.
    it 'rejects a second row even when validations are skipped' do
      duplicate = build(:dependency_management_remediation, **attributes)

      expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it 'allows the same dependency in another manifest' do
      expect { create(:dependency_management_remediation, **attributes, input_file_path: 'ui/package.json') }
        .to change { described_class.count }.by(1)
    end

    it 'allows the same package name under another ecosystem' do
      expect { create(:dependency_management_remediation, **attributes, purl_type: :pypi) }
        .to change { described_class.count }.by(1)
    end

    # npm allows the same package installed at several versions in one
    # manifest, each remediated on its own.
    it 'allows the same dependency at another installed version' do
      expect { create(:dependency_management_remediation, **attributes, current_version: '1.2.0') }
        .to change { described_class.count }.by(1)
    end
  end

  describe '#dismissed_at' do
    it 'reports updated_at while dismissed' do
      dismissed = create(:dependency_management_remediation, :dismissed, project: project)

      expect(dismissed.dismissed_at).to eq(dismissed.updated_at)
    end

    it 'is nil in every other state' do
      %i[open merged].each do |state|
        expect(build(:dependency_management_remediation, state: state).dismissed_at).to be_nil
      end
    end
  end

  context 'with loose foreign key on dependency_management_remediations.project_id' do
    it_behaves_like 'cleanup by a loose foreign key', on_delete: :async_delete do
      let_it_be(:parent) { create(:project) }
      let_it_be(:model) { create(:dependency_management_remediation, project: parent) }
    end
  end

  context 'with loose foreign key on dependency_management_remediations.merge_request_id' do
    # Nullify, not delete: a dismissal must survive its merge request.
    it_behaves_like 'cleanup by a loose foreign key', on_delete: :async_nullify do
      let_it_be(:parent) { create(:merge_request) }
      let_it_be(:model) do
        create(:dependency_management_remediation, project: parent.source_project, merge_request: parent)
      end
    end
  end
end
