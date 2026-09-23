# frozen_string_literal: true

# Requires `actions`, `declaring_type`, `allowed_actions`, `verdict_scope`, `verdict_read`,
# `expected_graphql_name`, `extra_action` (an action outside `actions`), and `missing_action`
# (an action inside `actions`) from the including spec.
RSpec.shared_examples 'an artifact registry permission type' do
  include GraphqlHelpers

  subject { described_class }

  let(:ctx) { { skip_type_authorization: [:read_artifact_registry] } }
  let(:slug) { 'resolved-handle' }
  let(:complete_attributes) { actions.index_with { |action| allowed_actions.include?(action) } }

  before do
    allow(Gitlab::ErrorTracking).to receive(:track_exception)
  end

  def verdicts_for(attributes)
    ArtifactRegistry::Permissions::Verdicts.new(attributes, scope: verdict_scope, read: verdict_read, slug: slug)
  end

  def block_for(verdicts)
    described_class::Block.new(verdicts: verdicts, declaring_type: declaring_type)
  end

  def resolved(block)
    actions.index_with { |action| resolve_field(action, block, ctx: ctx) }
  end

  specify { expect(described_class.graphql_name).to eq(expected_graphql_name) }

  it { is_expected.to require_graphql_authorizations(:read_artifact_registry) }

  it 'declares one non-null Boolean per action of the transcribed set, and no other field',
    :aggregate_failures do
    expect(described_class.fields.keys).to match_array(actions.map { |action| action.camelize(:lower) })
    expect(described_class.fields.values.map { |field| field.type.to_type_signature }).to all(eq('Boolean!'))
  end

  it 'marks every field experiment ahead of general availability' do
    expect(described_class.fields.values)
      .to all(have_attributes(deprecation_reason: a_string_including('Status: Experiment.')))
  end

  describe 'resolving a complete permissions object' do
    it 'mirrors each verdict and reports nothing', :aggregate_failures do
      expect(resolved(block_for(verdicts_for(complete_attributes)))).to eq(complete_attributes)
      expect(Gitlab::ErrorTracking).not_to have_received(:track_exception)
    end
  end

  describe 'resolving a permissions object carrying an action the set does not name' do
    it 'resolves the named actions, drops the extra, and reports nothing', :aggregate_failures do
      block = block_for(verdicts_for(complete_attributes.merge(extra_action => true)))

      expect(resolved(block)).to eq(complete_attributes)
      expect(described_class.fields).not_to have_key(extra_action.camelize(:lower))
      expect(Gitlab::ErrorTracking).not_to have_received(:track_exception)
    end
  end

  describe 'resolving a permissions object missing an action of the set' do
    let(:verdicts) { verdicts_for(complete_attributes.except(missing_action)) }

    it 'resolves every field false and reports the drift with the read, the slug, and the missing action',
      :aggregate_failures do
      expect(resolved(block_for(verdicts)).values).to all(be(false))
      expect(Gitlab::ErrorTracking).to have_received(:track_exception).with(
        instance_of(ArtifactRegistry::Permissions::VerdictReport::DriftError),
        { read: verdict_read, slug: slug, missing_actions: [missing_action] }
      )
    end
  end

  describe 'resolving an absent permissions object' do
    let(:verdicts) do
      ArtifactRegistry::Permissions::Verdicts.absent(scope: verdict_scope, read: verdict_read, slug: slug)
    end

    it 'resolves every field false and reports the absence with the read and the slug', :aggregate_failures do
      expect(resolved(block_for(verdicts)).values).to all(be(false))
      expect(Gitlab::ErrorTracking).to have_received(:track_exception).with(
        instance_of(ArtifactRegistry::Permissions::VerdictReport::AbsentError),
        { read: verdict_read, slug: slug }
      )
    end

    it 'reports once for the block, not once per field' do
      query = GraphQL::Query.new(GitlabSchema, document: nil, context: ctx, variables: {})
      instance = described_class.authorized_new(block_for(verdicts), query.context)

      expect(ArtifactRegistry::Permissions::VerdictReport).to receive(:absent).with(verdicts).once

      actions.each { |action| instance.public_send(action) }
    end
  end

  describe 'resolving a block that received no permissions object' do
    it 'resolves every field false and reports a defect scoped to the declaring type', :aggregate_failures do
      expect(resolved(block_for(nil)).values).to all(be(false))
      expect(Gitlab::ErrorTracking).to have_received(:track_exception).with(
        instance_of(ArtifactRegistry::Permissions::VerdictReport::DefectError),
        { scope: declaring_type }
      ).once
    end
  end
end
