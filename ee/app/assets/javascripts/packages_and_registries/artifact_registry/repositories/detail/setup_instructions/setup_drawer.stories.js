import SetupDrawer from './setup_drawer.vue';

export default {
  component: SetupDrawer,
  title: 'ee/artifact_registry/repositories/detail/setup_instructions/setup_drawer',
};

const Template =
  (format, kind = 'HOSTED') =>
  () => ({
    components: { SetupDrawer },
    provide: {
      slug: 'acme',
      clientBaseUrl: 'https://ar.gitlab.com',
    },
    data() {
      return { format, kind, open: false };
    },
    template: `
      <div>
        <button id="reopen" @click="open = true">Open setup instructions</button>
        <setup-drawer
          name="my-repository"
          :format="format"
          :kind="kind"
          :open="open"
          @close="open = false"
        />
      </div>
    `,
  });

export const Maven = Template('MAVEN');

export const Npm = Template('NPM');

export const Docker = Template('DOCKER');

export const Oci = Template('OCI');

export const Remote = Template('MAVEN', 'REMOTE');
