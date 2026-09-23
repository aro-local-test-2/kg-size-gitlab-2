import { GlDisclosureDropdownGroup, GlToggle } from '@gitlab/ui';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import ViewOptions from 'ee/packages_and_registries/artifact_registry/repositories/components/view_options.vue';
import VersionListViewOptions from 'ee/packages_and_registries/artifact_registry/repositories/versions/view_options.vue';

describe('ArtifactRegistryVersionListViewOptions', () => {
  let wrapper;

  const findViewOptions = () => wrapper.findComponent(ViewOptions);
  const findColumnLabels = () =>
    findViewOptions()
      .props('columns')
      .map(({ label }) => label);
  const findReferrersItem = () => wrapper.findByTestId('preference-item-referrers');
  const findReferrersToggle = () => findReferrersItem().findComponent(GlToggle);

  const createComponent = ({ format = 'MAVEN', ...props } = {}) => {
    wrapper = mountExtended(VersionListViewOptions, {
      propsData: { format, ...props },
    });
  };

  const clickReferrersItem = async () => {
    await findReferrersItem().find('button').trigger('click');
  };

  describe.each`
    format      | labels                                     | identityLabel | rendersPreferences
    ${'MAVEN'}  | ${['Size', 'Published', 'Source']}         | ${'Version'}  | ${false}
    ${'NPM'}    | ${['Tags', 'Size', 'Published', 'Source']} | ${'Version'}  | ${false}
    ${'DOCKER'} | ${['Type', 'Size', 'Published']}           | ${'Digest'}   | ${true}
    ${'OCI'}    | ${['Type', 'Size', 'Published']}           | ${'Digest'}   | ${true}
  `('for a $format artifact', ({ format, labels, identityLabel, rendersPreferences }) => {
    beforeEach(() => createComponent({ format }));

    it('offers one switch per optional column the format renders', () => {
      expect(findColumnLabels()).toEqual(labels);
    });

    it('offers no switch for the row-identity column', () => {
      expect(findColumnLabels()).not.toContain(identityLabel);
    });

    it('offers no switch for the actions column', () => {
      expect(findColumnLabels()).not.toContain('Actions');
    });

    it(`${rendersPreferences ? 'renders' : 'does not render'} the referrer preference`, () => {
      expect(findReferrersItem().exists()).toBe(rendersPreferences);
    });
  });

  it('passes the hidden columns through', () => {
    createComponent({ hiddenColumns: ['source'] });

    expect(findViewOptions().props('hiddenColumns')).toEqual(['source']);
  });

  it('re-emits a column change', () => {
    createComponent();

    findViewOptions().vm.$emit('input', ['source']);

    expect(wrapper.emitted('input')).toEqual([[['source']]]);
  });

  describe('the referrer manifests preference', () => {
    it('reads on by default, matching the value the view sends on first load', () => {
      createComponent({ format: 'DOCKER' });

      expect(findReferrersToggle().props()).toMatchObject({
        label: 'Referrer manifests',
        value: true,
      });
    });

    it('reads off when referrers are excluded', () => {
      createComponent({ format: 'DOCKER', includeReferrers: false });

      expect(findReferrersToggle().props('value')).toBe(false);
    });

    it.each([true, false])('emits the negation of %p when switched', async (includeReferrers) => {
      createComponent({ format: 'DOCKER', includeReferrers });

      await clickReferrersItem();

      expect(wrapper.emitted('referrers-changed')).toEqual([[!includeReferrers]]);
    });

    it('emits nothing on the columns channel, so the page cannot confuse the two', async () => {
      createComponent({ format: 'DOCKER' });

      await clickReferrersItem();

      expect(wrapper.emitted('input')).toBeUndefined();
    });

    it('separates itself from the columns section', () => {
      createComponent({ format: 'DOCKER' });

      expect(wrapper.findAllComponents(GlDisclosureDropdownGroup).at(1).props('bordered')).toBe(
        true,
      );
    });
  });
});
