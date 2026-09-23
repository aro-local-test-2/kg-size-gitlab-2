import { GlDisclosureDropdown, GlDisclosureDropdownItem } from '@gitlab/ui';
import { RouterLinkStub } from '@vue/test-utils';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import { EDIT_ROUTE_NAME } from 'ee/ci/secrets/constants';
import SecretActionsCell from 'ee/ci/secrets/components/secrets_table/secret_actions_cell.vue';

describe('SecretActionsCell component', () => {
  let wrapper;

  const findSecretActionItems = () => wrapper.findAllComponents(GlDisclosureDropdownItem);

  const createComponent = ({ props = {} } = {}) => {
    wrapper = mountExtended(SecretActionsCell, {
      propsData: {
        editRoute: { name: EDIT_ROUTE_NAME, params: { secretName: 'SECRET_KEY' } },
        secretName: 'SECRET_KEY',
        ...props,
      },
      stubs: {
        RouterLink: RouterLinkStub,
      },
    });
  };

  beforeEach(() => {
    createComponent();
  });

  it('shows the actions dropdown for the secret', () => {
    expect(findSecretActionItems()).toHaveLength(2);
  });

  describe('when the secret cannot be updated', () => {
    beforeEach(() => {
      createComponent({ props: { canUpdate: false } });
    });

    it('shows only the "Delete" action', () => {
      expect(findSecretActionItems()).toHaveLength(1);
      expect(findSecretActionItems().at(0).text()).toBe('Delete');
    });
  });

  describe('when the secret cannot be updated or deleted', () => {
    beforeEach(() => {
      createComponent({ props: { canUpdate: false, canDelete: false } });
    });

    it('does not render the dropdown', () => {
      expect(wrapper.findComponent(GlDisclosureDropdown).exists()).toBe(false);
    });
  });

  it('shows the "Edit secret" action', () => {
    const action = findSecretActionItems().at(0);

    expect(action.text()).toBe('Edit');
    expect(action.findComponent(RouterLinkStub).props('to')).toMatchObject({
      name: EDIT_ROUTE_NAME,
      params: { secretName: 'SECRET_KEY' },
    });
  });

  it('shows the "Delete" action', () => {
    const action = findSecretActionItems().at(1);

    expect(action.text()).toBe('Delete');

    action.vm.$emit('action');

    expect(wrapper.emitted('delete-secret')).toEqual([['SECRET_KEY']]);
  });
});
