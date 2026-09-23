import { defineFixtureVariants } from 'ee_jest/integration/core/fixture_variant_schema';

// The standalone workItemAgentPlan query has no Rails-generated fixture; the handler
// builds its response from the active variant's `content`. BASE resolves an empty plan;
// WITH_CONTENT carries the saved workplan content asserted by the details spec.
export default defineFixtureVariants({
  query: 'workItemAgentPlan',
  variants: {
    BASE: { data: { content: '', contentHtml: '', aiPlanningEnabled: true, readinessScore: null } },
    WITH_CONTENT: {
      data: {
        content: 'Existing workplan content',
        contentHtml: '<p>Existing workplan content</p>',
        aiPlanningEnabled: true,
        readinessScore: null,
      },
    },
    WITH_CONTENT_AND_SCORE: {
      data: {
        content: 'Existing workplan content',
        contentHtml: '<p>Existing workplan content</p>',
        aiPlanningEnabled: true,
        readinessScore: 72,
      },
    },
  },
});
