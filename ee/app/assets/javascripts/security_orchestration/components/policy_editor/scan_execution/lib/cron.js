import { getWeekdayNames } from '~/lib/utils/datetime_utility';
import { MAX_DAY_OF_MONTH } from '../../shared/cadence';
import {
  SCAN_EXECUTION_RULE_PERIOD_DAILY_KEY,
  SCAN_EXECUTION_RULE_PERIOD_WEEKLY_KEY,
  SCAN_EXECUTION_RULE_PERIOD_MONTHLY_KEY,
} from '../constants';

export const HOUR_MINUTE_LIST = Array.from(Array(24).keys()).reduce((acc, num) => {
  acc[num] = num.toString().length === 1 ? `0${num}:00` : `${num}:00`;
  return acc;
}, {});

export const DAYS = getWeekdayNames().reduce((acc, curr, i) => {
  acc[i] = curr;
  return acc;
}, {});

export const CRON_DEFAULT_TIME = '0 0 * * *';

const FIELD = { HOUR: 1, DAY_OF_MONTH: 2, DAY_OF_WEEK: 4 };
const WILDCARD = '*';

const isNumericField = (value) => /^\d{1,2}$/.test(value);
const isZero = (value) => isNumericField(value) && Number(value) === 0;
const isHour = (value) => isNumericField(value) && Number(value) <= 23;
const isWeekday = (value) => isNumericField(value) && Number(value) <= 6;
const isValidDaysOfMonth = (value) =>
  /^\d{1,2}(,\d{1,2})*$/.test(value) &&
  value.split(',').every((day) => Number(day) >= 1 && Number(day) <= MAX_DAY_OF_MONTH);

const parseDaysOfMonth = (value) =>
  [...new Set(value.split(',').map(Number))].sort((a, b) => a - b);

// The cadence is user-supplied YAML, so it may be null, non-string, or spaced
// irregularly. The backend's validators all split on arbitrary whitespace, so
// normalizing here keeps rule mode from rejecting a cadence they accept.
const cronFields = (cronString) =>
  String(cronString ?? '')
    .trim()
    .split(/\s+/);

// Deliberately stricter than "not a wildcard": an absent or malformed field
// must fall through to daily rather than be read as a weekday or a month day.
export const isCronWeekly = (cronString) => isWeekday(cronFields(cronString)[FIELD.DAY_OF_WEEK]);

export const isCronMonthly = (cronString) => {
  const fields = cronFields(cronString);
  return isValidDaysOfMonth(fields[FIELD.DAY_OF_MONTH]) && fields[FIELD.DAY_OF_WEEK] === WILDCARD;
};

export const getCronPeriod = (cronString) => {
  if (isCronMonthly(cronString)) return SCAN_EXECUTION_RULE_PERIOD_MONTHLY_KEY;
  if (isCronWeekly(cronString)) return SCAN_EXECUTION_RULE_PERIOD_WEEKLY_KEY;
  return SCAN_EXECUTION_RULE_PERIOD_DAILY_KEY;
};

/**
 * Creates cron syntax for a daily, weekly, or monthly schedule
 * @param {Number} time hour the scanner should run (0 through 23)
 * @param {Number} [day] day of the week for weekly schedules (0 through 6)
 * @param {Array<Number>} [daysOfMonth] days of the month for monthly schedules (1 through 31)
 * @returns {String} resulting cron syntax
 */
export const setCronTime = ({ time = 0, day, daysOfMonth } = {}) => {
  const fields = ['0', String(time), WILDCARD, WILDCARD, WILDCARD];

  if (daysOfMonth?.length) {
    fields[FIELD.DAY_OF_MONTH] = [...new Set(daysOfMonth)].sort((a, b) => a - b).join(',');
  } else if (day !== undefined && day !== null) {
    fields[FIELD.DAY_OF_WEEK] = String(day);
  }

  return fields.join(' ');
};

/**
 * Retrieves the schedule details from cron syntax
 * @param {String} cronString
 * @returns {Object} time, day (weekly), and daysOfMonth (monthly) of the schedule
 */
export const parseCronTime = (cronString) => {
  const fields = cronFields(cronString);
  // Normalized through Number so a zero-padded field ('07') keys into
  // HOUR_MINUTE_LIST and matches the listbox option value, rather than
  // silently falling back to midnight.
  const timeIndex = isHour(fields[FIELD.HOUR]) ? String(Number(fields[FIELD.HOUR])) : '0';
  const dayIndex = isCronWeekly(cronString) ? String(Number(fields[FIELD.DAY_OF_WEEK])) : '0';
  const daysOfMonth = isCronMonthly(cronString) ? parseDaysOfMonth(fields[FIELD.DAY_OF_MONTH]) : [];

  return {
    dayIndex,
    day: DAYS[dayIndex] || DAYS[0],
    timeIndex,
    time: HOUR_MINUTE_LIST[timeIndex] || HOUR_MINUTE_LIST[0],
    daysOfMonth,
  };
};

/**
 * Determines whether a cron cadence can be represented losslessly by the
 * rule-mode schedule builder, which supports a fixed minute of 0, a single
 * hour, and either a weekday or a list of month days. Cadences using ranges,
 * steps, minute offsets, or other cron features must be edited in YAML mode.
 * @param {String} cronString
 * @returns {Boolean}
 */
export const isCronRuleModeSupported = (cronString) => {
  const fields = cronFields(cronString);
  if (fields.length !== 5) return false;

  const [minute, hour, dayOfMonth, month, dayOfWeek] = fields;
  if (!isZero(minute) || !isHour(hour) || month !== WILDCARD) return false;

  if (dayOfMonth === WILDCARD && dayOfWeek === WILDCARD) return true;
  if (dayOfMonth === WILDCARD && isWeekday(dayOfWeek)) return true;
  if (dayOfWeek === WILDCARD && isValidDaysOfMonth(dayOfMonth)) return true;

  return false;
};
