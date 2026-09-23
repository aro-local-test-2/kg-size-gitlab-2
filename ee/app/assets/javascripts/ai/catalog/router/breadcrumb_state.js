import { observable } from '~/lib/utils/observable';

// Keyed by route param, not item id: the breadcrumb is a separate app that only shares the router.
export const itemKeyFromRoute = ({ params }) => params.reference || params.id;

export const breadcrumbState = observable('ai_catalog_breadcrumb', {
  itemKey: null,
  name: '',
  setName(itemKey, name) {
    this.itemKey = itemKey;
    this.name = name;
  },
  clearName() {
    this.itemKey = null;
    this.name = '';
  },
});
