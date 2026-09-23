import Vue from 'vue';
// eslint-disable-next-line no-restricted-imports
import Vuex from 'vuex';
import modalModule from '~/vuex_shared/modules/modal';
import state from './state';

Vue.use(Vuex);

export const createStoreOptions = (approvalsModules, settings) => ({
  state: state(settings),
  modules: {
    ...approvalsModules,
    deleteModal: modalModule(),
  },
});

export default (approvalModules, settings = {}) =>
  new Vuex.Store(createStoreOptions(approvalModules, settings));
