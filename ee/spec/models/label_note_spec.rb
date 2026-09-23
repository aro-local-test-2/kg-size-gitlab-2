# frozen_string_literal: true

require 'spec_helper'

RSpec.describe LabelNote do
  include Gitlab::Routing.url_helpers

  let_it_be(:group)  { create(:group) }
  let_it_be(:user)   { create(:user) }
  let_it_be(:label) { create(:group_label, group: group, title: 'label-1') }
  let_it_be(:label2) { create(:group_label, group: group, title: 'label-2') }
  let(:resource_parent) { group }
  let_it_be(:resource) { create(:epic, group: group) }

  let(:project) { nil }
  let(:resource_key) { resource.class.name.underscore.to_s }
  let(:events) { [create(:resource_label_event, label: label, resource_key => resource)] }

  subject { described_class.from_events(events, resource: resource, resource_parent: resource_parent) }

  context 'when resource is epic' do
    it_behaves_like 'label note created from events'

    it 'includes a link to the list of epics filtered by the label' do
      expect(subject.note_html).to include(group_epics_path(group, label_name: label.title))
    end
  end

  # Epic is the only group level work item today, so it is the one shape where
  # the note has to render against a group rather than a project.
  context 'when the resource is an epic work item' do
    let_it_be(:epic_work_item) { create(:work_item, :epic, :group_level, namespace: group) }
    let_it_be(:event, freeze: false) do
      create(:resource_label_event, issue: epic_work_item, label: label, namespace: group)
    end

    subject(:note) { event.work_item_synthetic_system_note }

    it 'renders against the group' do
      expect(note.resource_parent).to eq(group)
    end

    it 'links the label to the group work item list' do
      expect(note.note_html).to include(group_work_items_path(group, label_name: label.title))
      expect(note.note_html).to include(label.title)
    end
  end

  context 'when a label is removed' do
    it 'returns note correctly' do
      events
      label.destroy!
      events.first.reload

      expect(subject.note).to include('deleted label')
    end
  end
end
