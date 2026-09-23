import { s__ } from '~/locale';

export const MAX_DAY_OF_MONTH = 31;

export const MONTHLY_DAYS_LABEL = s__('SecurityOrchestration|Days of month');
export const SELECT_DAYS_HEADER = s__('SecurityOrchestration|Select days');

/**
 * Generate options for monthly day-of-month selection
 * @returns {Array<{value: Number, text: Number}>}
 */
export const getMonthlyDayOptions = () =>
  Array.from({ length: MAX_DAY_OF_MONTH }, (_, i) => {
    const day = i + 1;
    return { value: day, text: day };
  });
