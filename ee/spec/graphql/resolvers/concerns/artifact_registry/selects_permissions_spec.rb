# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ArtifactRegistry::SelectsPermissions, feature_category: :artifact_registry do
  include GraphqlHelpers

  let(:resolver_class) do
    Class.new(Resolvers::BaseResolver) do
      include ::ArtifactRegistry::SelectsPermissions

      def selected?(lookahead)
        permissions_selected?(lookahead)
      end

      def connection_selected?(lookahead)
        connection_permissions_selected?(lookahead)
      end
    end
  end

  let(:resolver) { resolver_class.new(object: nil, context: query_context(user: nil), field: nil) }

  it 'asks the field for the lookahead extra' do
    expect(resolver_class.extras).to include(:lookahead)
  end

  describe '#permissions_selected?' do
    it 'is true when the selection includes userPermissions' do
      lookahead = instance_double(GraphQL::Execution::Lookahead)
      allow(lookahead).to receive(:selects?).with(:user_permissions).and_return(true)

      expect(resolver.selected?(lookahead)).to be(true)
    end

    it 'is false when the selection omits userPermissions' do
      expect(resolver.selected?(negative_lookahead)).to be(false)
    end
  end

  describe '#connection_permissions_selected?' do
    def lookahead_selecting(*path)
      lookahead = instance_double(GraphQL::Execution::Lookahead)
      allow(lookahead).to receive(:selects?).with(:user_permissions).and_return(path.empty?)
      allow(lookahead).to receive(:selection) do |field_name|
        field_name == path.first ? lookahead_selecting(*path.drop(1)) : negative_lookahead
      end

      lookahead
    end

    it 'is true when the connection selects userPermissions' do
      expect(resolver.connection_selected?(lookahead_selecting)).to be(true)
    end

    it 'is true when a node under nodes selects userPermissions' do
      expect(resolver.connection_selected?(lookahead_selecting(:nodes))).to be(true)
    end

    it 'is true when a node under edges selects userPermissions' do
      expect(resolver.connection_selected?(lookahead_selecting(:edges, :node))).to be(true)
    end

    it 'is false when neither the connection nor its nodes select userPermissions' do
      expect(resolver.connection_selected?(negative_lookahead)).to be(false)
    end
  end
end
