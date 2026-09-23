# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::JsRoutes, feature_category: :tooling do
  describe '.generate!' do
    let_it_be(:expected_base_path) do
      Rails.root.join('ee/app/assets/javascripts/lib/utils/path_helpers')
    end

    describe 'outputted files' do
      before_all do
        described_class.generate!
      end

      describe 'path helpers are split into multiple files by namespace' do
        it 'generates project path helpers' do
          file_path = File.join(expected_base_path, 'project.js')
          expect(File).to exist(file_path)

          file_contents = File.read(file_path)
          expect(file_contents).to include("import { __jsr } from '~/lib/utils/path_helpers/core';")
          expect(file_contents).to include(
            "import { resolveOrganizationScope, splitProjectFullPath } from '~/lib/utils/path_helpers/utils';"
          )
          expect(file_contents).to include(
            "export const importCsvProjectRequirementsManagementRequirementsPath = /*#__PURE__*/ " \
              "(projectFullPath, ...args) => {"
          )
          expect(file_contents).to include(
            "const _importCsvOrganizationNamespaceProjectRequirementsManagementRequirementsPath = /*#__PURE__*/ " \
              "__jsr.r("
          )
          expect(file_contents).to include(
            "const _importCsvNamespaceProjectRequirementsManagementRequirementsPath = /*#__PURE__*/ __jsr.r("
          )
          expect(file_contents).to include(
            <<-JS
  const { namespacePath, projectPath } = splitProjectFullPath(projectFullPath);
  const { organizationPath, routeArgs } = resolveOrganizationScope(args);

  if (organizationPath) {
    return _importCsvOrganizationNamespaceProjectRequirementsManagementRequirementsPath(organizationPath, namespacePath, projectPath, ...routeArgs);
  }

  return _importCsvNamespaceProjectRequirementsManagementRequirementsPath(namespacePath, projectPath, ...routeArgs);
            JS
          )
        end

        it 'generates group path helpers' do
          file_path = File.join(expected_base_path, 'group.js')
          expect(File).to exist(file_path)

          file_contents = File.read(file_path)
          expect(file_contents).to include("import { __jsr } from '~/lib/utils/path_helpers/core';")
          expect(file_contents).to include(
            "import { resolveOrganizationScope } from '~/lib/utils/path_helpers/utils';"
          )
          expect(file_contents).to include(
            "export const groupSettingsReportingPath = /*#__PURE__*/ (...args) => {"
          )
          expect(file_contents).to include(
            "const _organizationGroupSettingsReportingPath = /*#__PURE__*/ __jsr.r("
          )
          expect(file_contents).to include(
            "const _groupSettingsReportingPath = /*#__PURE__*/ __jsr.r("
          )
          expect(file_contents).to include(
            <<-JS
  const { organizationPath, routeArgs } = resolveOrganizationScope(args);

  if (organizationPath) {
    return _organizationGroupSettingsReportingPath(organizationPath, ...routeArgs);
  }

  return _groupSettingsReportingPath(...routeArgs);
            JS
          )
        end
      end
    end
  end
end
