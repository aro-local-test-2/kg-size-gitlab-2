import base from 'test_fixtures/graphql/ai_duo_panel/integration/get_workflow_latest_checkpoint.query.graphql.json';
import archived from 'test_fixtures/graphql/ai_duo_panel/integration/get_workflow_latest_checkpoint_archived.query.graphql.json';
import firstThread from 'test_fixtures/graphql/ai_duo_panel/integration/get_workflow_latest_checkpoint_first_thread.query.graphql.json';
import secondThread from 'test_fixtures/graphql/ai_duo_panel/integration/get_workflow_latest_checkpoint_second_thread.query.graphql.json';
import withContext from 'test_fixtures/graphql/ai_duo_panel/integration/get_workflow_latest_checkpoint_with_context.query.graphql.json';
import { defineFixtureVariants } from 'ee_jest/integration/core/fixture_variant_schema';
import { setFixtureItemsCount } from 'ee_jest/integration/core/fixture_utils';

export default defineFixtureVariants({
  query: 'getWorkflowLatestCheckpoint',
  variants: {
    BASE: base,
    // Same capture as BASE. A spec selecting a conversation explicitly cannot ask for
    // BASE, because an active BASE means "no variant" and falls through.
    ACTIVE: base,
    ARCHIVED: archived,
    FIRST_THREAD: firstThread,
    SECOND_THREAD: secondThread,
    WITH_CONTEXT: withContext,
    // The query looks a workflow up by id, so an empty node list is how the API
    // says it does not exist. The chat reads that as a deleted thread.
    NOT_FOUND: setFixtureItemsCount({
      fixture: base,
      lookupKey: 'duoWorkflowWorkflows',
      itemCount: 0,
    }),
  },
});
