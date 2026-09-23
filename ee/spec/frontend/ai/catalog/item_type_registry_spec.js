import {
  AI_CATALOG_TYPE_AGENT,
  AI_CATALOG_TYPE_FLOW,
  AI_CATALOG_TYPE_THIRD_PARTY_FLOW,
  AI_CATALOG_TYPE_FOUNDATIONAL_AGENT,
} from 'ee/ai/catalog/constants';
import {
  itemTypeValidator,
  getRegistryItem,
  getRegistryTypes,
} from 'ee/ai/catalog/item_type_registry';

describe('item_type_registry', () => {
  it.each`
    type                                  | label
    ${AI_CATALOG_TYPE_AGENT}              | ${'agents'}
    ${AI_CATALOG_TYPE_FLOW}               | ${'flows'}
    ${AI_CATALOG_TYPE_THIRD_PARTY_FLOW}   | ${'third-party flows'}
    ${AI_CATALOG_TYPE_FOUNDATIONAL_AGENT} | ${'foundational agents'}
  `('validates and resolves $label', ({ type }) => {
    expect(itemTypeValidator(type)).toBe(true);
    expect(getRegistryItem(type)).toBeDefined();
  });

  it('rejects an unknown item type from the validator', () => {
    expect(itemTypeValidator('UNKNOWN')).toBe(false);
  });

  it('throws for an unknown item type', () => {
    expect(() => getRegistryItem('UNKNOWN')).toThrow('Unknown AI catalog item type: UNKNOWN');
  });

  it.each`
    type                                  | label                    | publicDescription
    ${AI_CATALOG_TYPE_AGENT}              | ${'agents'}              | ${'Anyone can view and use the agent.'}
    ${AI_CATALOG_TYPE_FLOW}               | ${'flows'}               | ${'Anyone can view and use the flow.'}
    ${AI_CATALOG_TYPE_THIRD_PARTY_FLOW}   | ${'third-party flows'}   | ${'Anyone can view and use the agent.'}
    ${AI_CATALOG_TYPE_FOUNDATIONAL_AGENT} | ${'foundational agents'} | ${'Anyone can view and use the agent.'}
  `(
    'uses the correct $label wording for the public visibility level',
    ({ type, publicDescription }) => {
      expect(getRegistryItem(type).visibilityDescriptions.PUBLIC).toBe(publicDescription);
    },
  );

  // AiCatalogListItem reads visibility tooltips straight off the registry, so every
  // type has to describe all visibility levels.
  it.each(getRegistryTypes())('describes every visibility level for %s', (type) => {
    expect(getRegistryItem(type).visibilityDescriptions).toEqual({
      PUBLIC: expect.any(String),
      RESTRICTED: expect.any(String),
      PRIVATE: expect.any(String),
    });
  });

  describe('flow index showActionItem', () => {
    const { showActionItem } = getRegistryItem(AI_CATALOG_TYPE_FLOW).index;

    it.each`
      scenario                                | foundational | isGroupNamespace | expected
      ${'foundational flow at group level'}   | ${true}      | ${true}          | ${false}
      ${'foundational flow at project level'} | ${true}      | ${false}         | ${true}
      ${'custom flow at group level'}         | ${false}     | ${true}          | ${true}
      ${'custom flow at project level'}       | ${false}     | ${false}         | ${true}
    `('returns $expected for $scenario', ({ foundational, isGroupNamespace, expected }) => {
      expect(showActionItem({ foundational }, true, { isGroupNamespace })).toBe(expected);
    });

    it('returns false without consumer admin permission', () => {
      expect(showActionItem({ foundational: false }, false, { isGroupNamespace: false })).toBe(
        false,
      );
    });
  });
});
