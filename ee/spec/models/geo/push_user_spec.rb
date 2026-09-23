# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Geo::PushUser, feature_category: :geo_replication do
  let!(:user) { create(:user) }
  let!(:key) { create(:key, user: user) }

  let(:gl_id) { "key-#{key.id}" }

  subject(:push_user) { described_class.new(gl_id) }

  describe '#user' do
    context 'with a junk gl_id' do
      let(:gl_id) { "test" }

      it 'returns nil' do
        expect(push_user.user).to be_nil
      end
    end

    context 'with an SSH key gl_id' do
      it 'returns the User associated with the Key' do
        expect(push_user.user).to eq(user)
      end

      context 'when there is no Key for the given ID' do
        let(:gl_id) { "key-#{non_existing_record_id}" }

        it 'returns nil' do
          expect(push_user.user).to be_nil
        end
      end
    end

    context 'with a user gl_id' do
      let(:gl_id) { "user-#{user.id}" }

      it 'returns the User' do
        expect(push_user.user).to eq(user)
      end

      context 'when there is no User for the given ID' do
        let(:gl_id) { "user-#{non_existing_record_id}" }

        it 'returns nil' do
          expect(push_user.user).to be_nil
        end
      end
    end

    context 'with a username gl_id as used by SSH certificate authentication' do
      let(:gl_id) { "username-#{user.username}" }

      it 'returns the User' do
        expect(push_user.user).to eq(user)
      end

      context 'when there is no User for the given username' do
        let(:gl_id) { "username-does-not-exist" }

        it 'returns nil' do
          expect(push_user.user).to be_nil
        end
      end

      context 'when the username looks like an SSH key gl_id' do
        let!(:other_user) { create(:user, username: "key-#{key.id}") }
        let(:gl_id) { "username-key-#{key.id}" }

        it 'returns the User with that username, not the Key owner' do
          expect(push_user.user).to eq(other_user)
        end
      end

      context 'when the username is numeric like a user ID' do
        let!(:other_user) { create(:user, username: user.id.to_s) }
        let(:gl_id) { "username-#{user.id}" }

        it 'returns the User with that username, not the User with that ID' do
          expect(push_user.user).to eq(other_user)
        end
      end
    end
  end

  describe '#deploy_key' do
    let!(:deploy_key) { create(:deploy_key) }

    context 'with a deploy key gl_id' do
      let(:gl_id) { "key-#{deploy_key.id}" }

      it 'returns the DeployKey' do
        expect(push_user.deploy_key).to eq(deploy_key)
      end
    end

    context 'with a user gl_id' do
      let(:gl_id) { "user-#{user.id}" }

      it 'returns nil' do
        expect(push_user.deploy_key).to be_nil
      end
    end

    context 'with a username gl_id' do
      let(:gl_id) { "username-#{user.username}" }

      it 'returns nil' do
        expect(push_user.deploy_key).to be_nil
      end
    end
  end
end
