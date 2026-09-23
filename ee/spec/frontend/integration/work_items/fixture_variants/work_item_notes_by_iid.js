import workItemNotesByIidBase from 'test_fixtures/graphql/work_items/integration/work_item_notes_by_iid.query.graphql.json';
import { defineFixtureVariants } from 'ee_jest/integration/core/fixture_variant_schema';
import { setFixtureData } from 'ee_jest/integration/core/fixture_utils';

const NOTE_AWARD_PERMISSION_PATH =
  'namespace.workItem.widgets[0].discussions.nodes[0].notes.nodes[0].userPermissions.awardEmoji';

export default defineFixtureVariants({
  query: 'workItemNotesByIid',
  variants: {
    BASE: workItemNotesByIidBase,
    LOCKED: setFixtureData(workItemNotesByIidBase, 'discussionLocked', true),
    // Path selector, not a key walk: awardEmoji also names the reaction connection
    // on the same note, so a first-match walk would blank the reactions instead.
    NO_AWARD_PERMISSION: setFixtureData(
      workItemNotesByIidBase,
      { path: NOTE_AWARD_PERMISSION_PATH },
      false,
    ),
  },
});
