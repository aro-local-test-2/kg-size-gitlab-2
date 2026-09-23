import { mountExtended } from 'helpers/vue_test_utils_helper';
import AdvancedConfigurationTable from 'ee/security_configuration/components/scan_profiles/advanced_configuration_table.vue';

describe('AdvancedConfigurationTable', () => {
  let wrapper;

  const sharedRow = {
    setting: 'excludedPaths',
    value: 'spec/,tmp/',
    triggerValues: [
      { triggerType: 'MERGE_REQUEST_PIPELINE', value: 'spec/,tmp/' },
      { triggerType: 'DEFAULT_BRANCH_PIPELINE', value: 'spec/,tmp/' },
    ],
  };

  const varyingRow = {
    setting: 'historicScan',
    varies: true,
    triggerValues: [
      { triggerType: 'MERGE_REQUEST_PIPELINE', value: 'Yes' },
      { triggerType: 'DEFAULT_BRANCH_PIPELINE', value: 'No' },
    ],
  };

  const sharedTriggerValues = [
    'Merge Request Pipelines',
    'spec/,tmp/',
    'Branch pipelines (default only)',
    'spec/,tmp/',
  ];

  const varyingTriggerValues = [
    'Merge Request Pipelines',
    'Yes',
    'Branch pipelines (default only)',
    'No',
  ];

  const createComponent = (rows) => {
    wrapper = mountExtended(AdvancedConfigurationTable, {
      propsData: { caption: 'Settings that apply across this profile', rows },
    });
  };

  const findVariableRow = () => wrapper.find('tbody tr:not(.b-table-details)');
  const findToggle = () => findVariableRow().find('button');
  const findVariableCell = () => findVariableRow().findAll('td').at(1);
  const findValueCell = () => findVariableRow().findAll('td').at(2);
  const findTriggerValues = () =>
    wrapper
      .findByTestId('trigger-values')
      .findAll('span')
      .wrappers.map((value) => value.text());

  it('shows a value shared by every trigger', () => {
    createComponent([sharedRow]);

    expect(findVariableCell().text()).toBe('excludedPaths');
    expect(findValueCell().text()).toBe('spec/,tmp/');
  });

  it('shows that a value differs by trigger', () => {
    createComponent([varyingRow]);

    expect(findVariableCell().text()).toBe('historicScan');
    expect(findValueCell().text()).toBe('Differs by trigger');
  });

  it.each`
    description  | row           | expected
    ${'shared'}  | ${sharedRow}  | ${sharedTriggerValues}
    ${'varying'} | ${varyingRow} | ${varyingTriggerValues}
  `('shows a value per trigger in a $description row', async ({ row, expected }) => {
    createComponent([row]);

    await findToggle().trigger('click');

    expect(findTriggerValues()).toEqual(expected);
  });
});
