# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Namespaces::ServiceAccounts::ProjectUpdateService, feature_category: :user_management do
  let_it_be(:organization) { create(:common_organization) }
  let_it_be(:group) { create(:group, organization: organization) }
  let_it_be(:subgroup) { create(:group, parent: group, organization: organization) }
  let_it_be(:project) { create(:project, group: subgroup) }
  let_it_be(:owner) { create(:user) }

  let(:service_account_user) { create(:user, :service_account, provisioned_by_project_id: project.id) }

  let(:params) do
    {
      name: FFaker::Name.name,
      username: "service_account_#{SecureRandom.hex(8)}",
      email: 'test@test.com',
      project_id: project.id
    }
  end

  let(:current_user) { owner }

  subject(:service) { described_class.new(current_user, service_account_user, params) }

  before_all do
    project.add_owner(owner)
  end

  describe '#execute' do
    context 'when email confirmation setting is set to hard' do
      before do
        stub_application_setting_enum('email_confirmation_setting', 'hard')
        stub_licensed_features(domain_verification: true)
      end

      context 'when SaaS', :saas do
        context 'when the root ancestor owns the email domain' do
          before do
            create(:pages_domain, project: create(:project, group: group), domain: 'test.com')
          end

          it 'updates the email without confirmation', :aggregate_failures do
            result = service.execute

            expect(result.status).to eq(:success)
            expect(result.payload[:user].email).to eq(params[:email])
            expect(result.payload[:user].unconfirmed_email).to be_nil
          end

          context 'when the project is directly under the top-level group' do
            let_it_be(:root_group_project) { create(:project, group: group) }

            let(:service_account_user) do
              create(:user, :service_account, provisioned_by_project_id: root_group_project.id)
            end

            let(:params) { super().merge(project_id: root_group_project.id) }

            before_all do
              root_group_project.add_owner(owner)
            end

            it 'updates the email without confirmation', :aggregate_failures do
              result = service.execute

              expect(result.status).to eq(:success)
              expect(result.payload[:user].email).to eq(params[:email])
              expect(result.payload[:user].unconfirmed_email).to be_nil
            end
          end

          context 'when the current user is a subgroup owner with no root group membership' do
            let_it_be(:current_user) { create(:user, owner_of: subgroup) }

            it 'updates the email without confirmation', :aggregate_failures do
              result = service.execute

              expect(result.status).to eq(:success)
              expect(result.payload[:user].email).to eq(params[:email])
              expect(result.payload[:user].unconfirmed_email).to be_nil
            end
          end

          context 'when the current user is a project maintainer with no root group membership' do
            let_it_be(:current_user) { create(:user, maintainer_of: project) }

            it 'updates the email without confirmation', :aggregate_failures do
              result = service.execute

              expect(result.status).to eq(:success)
              expect(result.payload[:user].email).to eq(params[:email])
              expect(result.payload[:user].unconfirmed_email).to be_nil
            end
          end
        end

        context 'when the root ancestor owns the email domain but has not verified it' do
          before do
            create(:pages_domain, :unverified, project: create(:project, group: group), domain: 'test.com')
          end

          it 'requires confirmation of the new email', :aggregate_failures do
            result = service.execute

            expect(result.status).to eq(:success)
            expect(result.payload[:user].unconfirmed_email).to eq(params[:email])
          end
        end

        context 'when another top-level group owns the email domain' do
          let_it_be(:other_group) { create(:group, organization: organization) }

          before do
            create(:pages_domain, project: create(:project, group: other_group), domain: 'test.com')
          end

          it 'requires confirmation of the new email', :aggregate_failures do
            result = service.execute

            expect(result.status).to eq(:success)
            expect(result.payload[:user].unconfirmed_email).to eq(params[:email])
          end
        end

        context 'when no group owns the email domain' do
          it 'requires confirmation of the new email', :aggregate_failures do
            result = service.execute

            expect(result.status).to eq(:success)
            expect(result.payload[:user].unconfirmed_email).to eq(params[:email])
          end
        end

        context 'when the project is in a personal namespace' do
          let_it_be(:personal_project) { create(:project, :in_user_namespace) }

          let(:service_account_user) do
            create(:user, :service_account, provisioned_by_project_id: personal_project.id)
          end

          let(:params) { super().merge(project_id: personal_project.id) }
          let(:current_user) { personal_project.first_owner }

          it 'requires confirmation of the new email', :aggregate_failures do
            result = service.execute

            expect(result.status).to eq(:success)
            expect(result.payload[:user].unconfirmed_email).to eq(params[:email])
          end
        end
      end

      context 'when self-managed' do
        before do
          create(:pages_domain, project: create(:project, group: group), domain: 'test.com')
        end

        it 'requires confirmation of the new email', :aggregate_failures do
          result = service.execute

          expect(result.status).to eq(:success)
          expect(result.payload[:user].unconfirmed_email).to eq(params[:email])
        end
      end
    end
  end
end
