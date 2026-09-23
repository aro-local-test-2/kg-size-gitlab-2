import createEventHub from '~/helpers/event_hub_factory';

// Its own module so both Vue lanes share one hub: the Duo panel in `main_ee`
// emits, and widgets inside Vue 3 pages subscribe. Import nothing that is exposed to Vue.
export default createEventHub();
