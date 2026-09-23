# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Organizations::Transfer::UsersService, :aggregate_failures, feature_category: :organization do
  let_it_be(:old_organization, freeze: false) { create(:organization) }
  let_it_be(:new_organization) { create(:organization) }
  let_it_be_with_refind(:group) { create(:group, organization: old_organization) }

  let(:users) { group.users_with_descendants }
  let(:service) { described_class.new(users: users, new_organization: new_organization) }

  describe '#execute', :eager_load do
    shared_context 'with transferred and non-group users' do
      let_it_be_with_refind(:user1) { create(:user, organization: old_organization) }
      let_it_be_with_refind(:non_group_user) { create(:user, organization: old_organization) }

      before_all do
        group.add_developer(user1)
      end
    end

    shared_context 'with personal snippet setup' do
      include_context 'with transferred and non-group users'

      let_it_be_with_refind(:personal_snippet) do
        create(:personal_snippet, author: user1, organization: old_organization)
      end

      let_it_be_with_refind(:non_group_snippet) do
        create(:personal_snippet, author: non_group_user, organization: old_organization)
      end
    end

    context 'with personal snippet repository states' do
      include_context 'with personal snippet setup'

      before_all do
        Users::Internal.in_organization(old_organization).ghost
      end

      before do
        service.prepare_bots
      end

      it 'updates snippet_organization_id for personal snippet repository states of transferred users' do
        snippet_repo = create(:snippet_repository, snippet: personal_snippet)
        repository_state = create(:geo_snippet_repository_state, snippet_repository: snippet_repo)

        service.execute

        expect(repository_state.reload.snippet_organization_id).to eq(new_organization.id)
      end

      it 'does not update snippet repository states for users not in the group' do
        non_group_repo = create(:snippet_repository, snippet: non_group_snippet)
        non_group_state = create(:geo_snippet_repository_state, snippet_repository: non_group_repo)

        expect { service.execute }.not_to change { non_group_state.reload.snippet_organization_id }
      end
    end

    context 'with snippet upload trigger-fire transfers' do
      include_context 'with personal snippet setup'

      context 'for snippet_uploads' do
        it 'updates organization_id via trigger for snippet uploads of transferred users' do
          upload = create(:upload, :with_file, model: personal_snippet)
          snippet_upload = Geo::PersonalSnippetUpload.find(upload.id)

          expect(snippet_upload.organization_id).to eq(old_organization.id)

          service.execute

          expect(snippet_upload.reload.organization_id).to eq(new_organization.id)
        end

        it 'does not update snippet uploads for users not in the group' do
          upload = create(:upload, :with_file, model: non_group_snippet)
          snippet_upload = Geo::PersonalSnippetUpload.find(upload.id)

          expect { service.execute }.not_to change { snippet_upload.reload.organization_id }
        end
      end

      context 'when batching snippet upload trigger updates' do
        include_context 'with transfer batch size of 1'

        let(:execute_service) { service.execute }
        let(:expected_batch_queries) { { 'snippet_uploads' => 3 } }

        before do
          3.times do
            snippet = create(:personal_snippet, author: user1, organization: old_organization)
            create(:upload, :with_file, model: snippet)
          end
        end

        it_behaves_like 'generates batched transfer queries'
      end
    end

    context 'with abuse report upload states' do
      include_context 'with transferred and non-group users'

      it 'updates organization_id for upload states of transferred reports' do
        state = upload_state_for(create(:abuse_report, reporter: user1, organization: old_organization))

        expect(state.organization_id).to eq(old_organization.id)

        service.execute

        expect(state.reload.organization_id).to eq(new_organization.id)
      end

      it 'does not update upload states of reports filed by users not in the group' do
        state = upload_state_for(create(:abuse_report, reporter: non_group_user, organization: old_organization))

        expect { service.execute }.not_to change { state.reload.organization_id }
      end

      def upload_state_for(abuse_report)
        upload = create(:upload, model: abuse_report, uploader: 'AttachmentUploader', mount_point: :screenshot)
        state = ::Geo::AbuseReportUpload.find(upload.id).abuse_report_upload_state
        state.save! unless state.persisted?

        state.reload
      end
    end

    context 'with AI conversation messages' do
      let_it_be_with_refind(:user1) { create(:user, organization: old_organization) }
      let_it_be_with_refind(:non_group_user) { create(:user, organization: old_organization) }

      before_all do
        group.add_developer(user1)
        Users::Internal.in_organization(old_organization).ghost
      end

      before do
        service.prepare_bots
      end

      it 'updates organization_id for AI conversation messages of transferred users' do
        thread = create(:ai_conversation_thread, user: user1, organization: old_organization)
        message = create(:ai_conversation_message, thread: thread, organization: old_organization)

        service.execute

        expect(message.reload.organization_id).to eq(new_organization.id)
      end

      it 'does not update AI conversation messages for users not in the group' do
        thread = create(:ai_conversation_thread, user: non_group_user, organization: old_organization)
        message = create(:ai_conversation_message, thread: thread, organization: old_organization)

        expect { service.execute }.not_to change { message.reload.organization_id }
      end

      it 'does not update AI conversation messages from a different organization' do
        other_org = create(:organization)
        thread = create(:ai_conversation_thread, user: user1, organization: other_org)
        message = create(:ai_conversation_message, thread: thread, organization: other_org)

        expect { service.execute }.not_to change { message.reload.organization_id }
      end

      context 'when batching message updates' do
        include_context 'with transfer batch size of 1'

        let_it_be_with_refind(:user2) { create(:user, organization: old_organization) }
        let_it_be_with_refind(:user3) { create(:user, organization: old_organization) }
        let(:execute_service) { service.execute }
        let(:expected_batch_queries) do
          { 'ai_conversation_messages' => 3 }
        end

        let!(:message1) do
          thread = create(:ai_conversation_thread, user: user1, organization: old_organization)
          create(:ai_conversation_message, thread: thread, organization: old_organization)
        end

        let!(:message2) do
          thread = create(:ai_conversation_thread, user: user2, organization: old_organization)
          create(:ai_conversation_message, thread: thread, organization: old_organization)
        end

        let!(:message3) do
          thread = create(:ai_conversation_thread, user: user3, organization: old_organization)
          create(:ai_conversation_message, thread: thread, organization: old_organization)
        end

        before_all do
          group.add_developer(user2)
          group.add_developer(user3)
        end

        it 'processes all records across multiple batches' do
          service.execute

          expect(message1.reload.organization_id).to eq(new_organization.id)
          expect(message2.reload.organization_id).to eq(new_organization.id)
          expect(message3.reload.organization_id).to eq(new_organization.id)
        end

        it_behaves_like 'generates batched transfer queries'

        context 'when a single thread has more messages than the batch size' do
          let(:expected_batch_queries) do
            { 'ai_conversation_messages' => 5 }
          end

          let!(:extra_message1) do
            create(:ai_conversation_message, thread: message1.thread, organization: old_organization)
          end

          let!(:extra_message2) do
            create(:ai_conversation_message, thread: message1.thread, organization: old_organization)
          end

          it 'updates all messages in the thread across batches' do
            service.execute

            expect(extra_message1.reload.organization_id).to eq(new_organization.id)
            expect(extra_message2.reload.organization_id).to eq(new_organization.id)
          end

          it_behaves_like 'generates batched transfer queries'
        end
      end
    end

    context 'with user upload states' do
      include_context 'with transferred and non-group users'

      it 'updates organization_id for user upload states of transferred users' do
        upload = create(:upload, :with_file, model: user1)
        state = Geo::UserUpload.find(upload.id).user_upload_state
        state.update!(verification_state: 1)

        expect(state.reload.organization_id).to eq(old_organization.id)

        service.execute

        expect(state.reload.organization_id).to eq(new_organization.id)
      end

      it 'does not update user upload states for users not in the group' do
        upload = create(:upload, :with_file, model: non_group_user)
        state = Geo::UserUpload.find(upload.id).user_upload_state
        state.update!(verification_state: 1)

        expect { service.execute }.not_to change { state.reload.organization_id }
      end

      context 'when batching user upload state updates' do
        include_context 'with transfer batch size of 1'

        let(:execute_service) { service.execute }
        let(:expected_batch_queries) { { 'user_upload_states' => 3 } }

        before do
          3.times do
            upload = create(:upload, :with_file, model: user1)
            Geo::UserUpload.find(upload.id).user_upload_state.update!(verification_state: 1)
          end
        end

        it_behaves_like 'generates batched transfer queries'
      end
    end
  end
end
