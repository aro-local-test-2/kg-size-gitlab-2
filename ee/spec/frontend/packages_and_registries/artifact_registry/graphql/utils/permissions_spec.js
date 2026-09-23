import { permissionAllows } from 'ee/packages_and_registries/artifact_registry/graphql/utils/permissions';

describe('permissionAllows', () => {
  it('is true on an explicit true', () => {
    expect(permissionAllows({ updateRepository: true }, 'updateRepository')).toBe(true);
  });

  it.each([undefined, null, true, 'allowed'])('is false for an unresolved block, %p', (block) => {
    expect(permissionAllows(block, 'updateRepository')).toBe(false);
  });

  it.each([false, null, undefined, 'true', 1, {}])('is false for a verdict of %p', (verdict) => {
    expect(permissionAllows({ updateRepository: verdict }, 'updateRepository')).toBe(false);
  });

  it('is false for an action the block does not carry', () => {
    expect(permissionAllows({ deleteRepository: true }, 'updateRepository')).toBe(false);
  });
});
