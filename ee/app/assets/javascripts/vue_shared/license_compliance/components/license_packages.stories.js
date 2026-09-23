import LicensePackages from './license_packages.vue';

const packages = [
  {
    name: 'pg',
  },
  {
    name: 'puma',
  },
  {
    name: 'rubocop',
  },
  {
    name: 'sidekiq',
  },
  {
    name: 'webpack',
  },
];

export default {
  component: LicensePackages,
  title: 'ee/vue_shared/license_compliance/license_packages',
};

const Template = (args, { argTypes }) => ({
  components: { LicensePackages },
  props: Object.keys(argTypes),
  template: '<license-packages v-bind="$props" />',
});

export const Default = Template.bind({});
Default.args = {
  packages,
};

export const SinglePackage = Template.bind({});
SinglePackage.args = {
  packages: [packages[0]],
};

export const ShortPackageList = Template.bind({});
ShortPackageList.args = {
  packages: packages.slice(0, 3),
};
