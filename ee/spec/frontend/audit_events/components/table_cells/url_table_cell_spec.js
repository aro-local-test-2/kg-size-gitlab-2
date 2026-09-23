import { shallowMountExtended } from 'helpers/vue_test_utils_helper';

import UrlTableCell from 'ee/audit_events/components/table_cells/url_table_cell.vue';

describe('UrlTableCell component', () => {
  let wrapper;

  const createComponent = (propsData) => {
    wrapper = shallowMountExtended(UrlTableCell, { propsData });
  };

  const findLink = () => wrapper.find('a');
  const findUnlinkedName = () => wrapper.findByTestId('unlinked-name');

  it('should show the link if the URL is provided', () => {
    createComponent({ url: '/user-1', name: 'User 1' });

    expect(findLink().exists()).toBe(true);
    expect(findLink().attributes('href')).toBe('/user-1');
    expect(findLink().text()).toBe('User 1');
  });

  it('should show the removed text if no URL is provided', () => {
    createComponent({ url: '', name: 'User 1' });

    expect(findUnlinkedName().exists()).toBe(true);
    expect(findUnlinkedName().text()).toBe('User 1 (removed)');
  });

  it.each`
    removed  | name                | expected
    ${false} | ${'(System)'}       | ${'(System)'}
    ${true}  | ${'A deleted user'} | ${'A deleted user (removed)'}
  `(
    'renders "$expected" when removed=$removed and no URL is provided',
    ({ removed, name, expected }) => {
      createComponent({ url: '', name, removed });

      expect(findUnlinkedName().text()).toBe(expected);
    },
  );
});
