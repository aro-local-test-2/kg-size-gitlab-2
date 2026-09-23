import LicenseIssueBody from './license_issue_body.vue';

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
];

const licenseIssue = {
  name: 'New BSD',
  url: 'https://opensource.org/licenses/BSD-3-Clause',
  packages,
};

export default {
  component: LicenseIssueBody,
  title: 'ee/vue_shared/license_compliance/license_issue_body',
};

const Template = (args, { argTypes }) => ({
  components: { LicenseIssueBody },
  props: Object.keys(argTypes),
  template: '<license-issue-body v-bind="$props" />',
});

export const Default = Template.bind({});
Default.args = {
  issue: licenseIssue,
};

export const WithoutLink = Template.bind({});
WithoutLink.args = {
  issue: {
    ...licenseIssue,
    name: 'MIT',
    url: undefined,
  },
};

export const WithoutPackages = Template.bind({});
WithoutPackages.args = {
  issue: {
    ...licenseIssue,
    packages: [],
  },
};
