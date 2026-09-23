# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Namespaces::ServiceAccounts::GroupUpdateService, feature_category: :user_management do
  let_it_be(:organization) { create(:common_organization) }
  let_it_be(:group) { create(:group, organization: organization) }
  let_it_be(:owner) { create(:user, owner_of: group) }

  let(:service_account_user) { create(:user, :service_account, provisioned_by_group: group) }

  let(:params) do
    {
      name: FFaker::Name.name,
      username: "service_account_#{SecureRandom.hex(8)}",
      email: 'test@test.com',
      group_id: group.id
    }
  end

  subject(:service) { described_class.new(owner, service_account_user, params) }

  describe '#execute' do
    context 'when email confirmation setting is set to hard' do
      before do
        stub_application_setting_enum('email_confirmation_setting', 'hard')
        stub_licensed_features(domain_verification: true)
      end

      context 'when SaaS', :saas do
        let_it_be(:subgroup) { create(:group, parent: group, organization: organization) }

        let(:service_account_user) { create(:user, :service_account, provisioned_by_group: subgroup) }
        let(:params) { super().merge(group_id: subgroup.id) }

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

          context 'when the service account belongs to the top-level group' do
            let(:service_account_user) { create(:user, :service_account, provisioned_by_group: group) }
            let(:params) { super().merge(group_id: group.id) }

            it 'updates the email without confirmation', :aggregate_failures do
              result = service.execute

              expect(result.status).to eq(:success)
              expect(result.payload[:user].email).to eq(params[:email])
              expect(result.payload[:user].unconfirmed_email).to be_nil
            end
          end

          context 'when the current user is a subgroup owner with no root group membership' do
            let_it_be(:owner) { create(:user, owner_of: subgroup) }

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
