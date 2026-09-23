import '../../../../../../../app/assets/stylesheets/page_bundles/reports.scss';
import LicenseStatusIcon from './license_status_icon.vue';

const STATUS_FAILED = 'failed';
const STATUS_NEUTRAL = 'neutral';
const STATUS_SUCCESS = 'success';

const statuses = [STATUS_SUCCESS, STATUS_NEUTRAL, STATUS_FAILED];

export default {
  component: LicenseStatusIcon,
  title: 'ee/vue_shared/license_compliance/license_status_icon',
  argTypes: {
    status: {
      control: 'select',
      options: statuses,
    },
    statusIconSize: {
      control: 'number',
    },
  },
};

const Template = (args, { argTypes }) => ({
  components: { LicenseStatusIcon },
  props: Object.keys(argTypes),
  template: '<license-status-icon v-bind="$props" />',
});

export const Default = Template.bind({});
Default.args = {
  status: STATUS_SUCCESS,
  statusIconSize: 12,
};

export const Neutral = Template.bind({});
Neutral.args = {
  status: STATUS_NEUTRAL,
  statusIconSize: 12,
};

export const Failed = Template.bind({});
Failed.args = {
  status: STATUS_FAILED,
  statusIconSize: 12,
};

export const AllStatuses = (args, { argTypes }) => ({
  components: { LicenseStatusIcon },
  props: Object.keys(argTypes),
  data() {
    return {
      statuses,
    };
  },
  template: `
    <div class="gl-flex gl-gap-3">
      <license-status-icon
        v-for="status in statuses"
        :key="status"
        :status="status"
        :status-icon-size="statusIconSize"
      />
    </div>
  `,
});
AllStatuses.args = {
  statusIconSize: 12,
};
AllStatuses.parameters = {
  controls: {
    exclude: ['status'],
  },
};
