import { shallowMount } from '@vue/test-utils';
import { GlFormCheckbox, GlFormGroup } from '@gitlab/ui';
import DuoWebSearchForm from 'ee/ai/settings/components/duo_web_search_form.vue';

describe('DuoWebSearchForm', () => {
  let wrapper;

  const createComponent = ({ props = {} } = {}) => {
    wrapper = shallowMount(DuoWebSearchForm, {
      propsData: {
        webSearchEnabled: false,
        ...props,
      },
      stubs: {
        GlFormCheckbox,
        GlFormGroup,
      },
    });
  };

  const findFormGroup = () => wrapper.findComponent(GlFormGroup);
  const findCheckbox = () => wrapper.findComponent(GlFormCheckbox);
  const findCheckboxLabel = () => findCheckbox().find('span');

  beforeEach(() => {
    createComponent();
  });

  it('renders the section title', () => {
    expect(findFormGroup().attributes('label')).toBe('Web search');
  });

  it('renders the checkbox label', () => {
    expect(findCheckboxLabel().text()).toBe('Allow web search');
  });

  it('renders the help text', () => {
    expect(findCheckbox().text()).toContain(
      'When enabled, GitLab Duo Chat can send user questions to an external search provider to find current information. Users still choose to turn on web search in each conversation.',
    );
  });

  it('exposes the checkbox under a stable test id', () => {
    expect(wrapper.find('[data-testid="web-search-enabled-checkbox"]').exists()).toBe(true);
  });

  it('names the checkbox after the attribute the settings API expects', () => {
    expect(findCheckbox().props('name')).toBe(
      'namespace[ai_settings_attributes][web_search_enabled]',
    );
  });

  it.each`
    webSearchEnabled | description
    ${true}          | ${'checked'}
    ${false}         | ${'unchecked'}
  `(
    'renders the checkbox as $description when webSearchEnabled is $webSearchEnabled',
    ({ webSearchEnabled }) => {
      createComponent({ props: { webSearchEnabled } });

      expect(findCheckbox().props('checked')).toBe(webSearchEnabled);
    },
  );

  it.each([[true], [false]])('sets the checkbox disabled state to %p', (disabledCheckbox) => {
    createComponent({ props: { disabledCheckbox } });

    expect(findCheckbox().props('disabled')).toBe(disabledCheckbox);
  });

  it.each([[true], [false]])('emits change with %p when the checkbox is toggled', (value) => {
    findCheckbox().vm.$emit('change', value);

    expect(wrapper.emitted('change')).toEqual([[value]]);
  });
});
