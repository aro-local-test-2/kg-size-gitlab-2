/**
 * Parses the clarifying question the workplan flow attaches to a comment it
 * posts on a work item.
 *
 * The flow posts an ordinary GFM comment, so the question stays readable in
 * email, in the REST API, and before this bundle runs. A machine-readable copy
 * of the same question rides along in the body, and this turns that copy into
 * something the UI can render.
 *
 * Two shapes are accepted. The fenced block is the richer one:
 *
 *     ```json:duo-question
 *     {"type": "closed", "question": "...", "multiple": false, "options": [
 *       {"id": "bump", "label": "...", "description": "...", "recommended": true}
 *     ]}
 *     ```
 *
 * Banzai renders it as `pre[data-canonical-lang="json"][data-lang-params="duo-question"]`,
 * which the sanitizer already allows through. The HTML comment marker is what
 * the flow emits today:
 *
 *     <!-- duo:options ["Okta", "Entra ID"] duo:recommended 1 duo:multiple -->
 *
 * Reading the raw note body rather than the rendered HTML keeps this
 * independent of how Banzai marks either shape up.
 *
 * The payload is written by a model, so it is treated as untrusted. Rather than
 * collapsing every failure into one empty value, parsing reports which of three
 * things happened, so a corrupted payload can be told apart from a comment that
 * never carried one:
 *
 *     { status: 'none' }                        ordinary comment, nothing to do
 *     { status: 'ok', question, diagnostics }   renderable, log any diagnostics
 *     { status: 'invalid', diagnostics }        payload present but unusable
 *
 * A question survives partial corruption: options that fail validation are
 * dropped and reported in `diagnostics` while the rest still render.
 */

import {
  ANSWER_ID_CUSTOM,
  PARSE_STATUS_INVALID,
  PARSE_STATUS_NONE,
  PARSE_STATUS_OK,
  QUESTION_TYPE_CLOSED,
  QUESTION_TYPE_OPEN,
} from '../constants';

// Anchored to a line start, with the up-to-3-space indent CommonMark allows, so
// prose that merely mentions the fence inline is not mistaken for a payload.
// Mirrored by FENCE_REGEX in ee/lib/ee/gitlab/work_items/duo_question.rb, which
// rewrites the same payload for email. Keep the two in sync.
const FENCE_RE = /^ {0,3}```json:duo-question[^\n]*\n([\s\S]*?)^ {0,3}```/m;

// Mirrored by MARKER_REGEX in ee/lib/ee/gitlab/work_items/duo_question.rb.
const MARKER_RE = /<!--\s*duo:options\s*([\s\S]*?)-->/;
const MARKER_ARRAY_RE = /(\[[\s\S]*?\])/;
const MARKER_RECOMMENDED_RE = /duo:recommended\s*(\d+)/;

// The marker's shape, defined once and used two ways below, so a change to the format
// cannot leave reading and stripping disagreeing about what a marker looks like.
const ANSWER_MARKER = String.raw`<!--\s*duo-answer:\s*([^\s>]+)\s*-->`;

// Reading an id needs the line anchor, like the fence above, so a reply quoting an
// earlier answer does not read as a fresh one: a blockquote line starts with `>`.
const ANSWER_MARKER_RE = new RegExp(String.raw`^ {0,3}${ANSWER_MARKER}`, 'm');

// Stripping needs neither the anchor nor a single match: removing only the anchored one
// would promote the next marker to the line start, where it would read back instead.
const ANSWER_MARKER_ANYWHERE_RE = new RegExp(ANSWER_MARKER, 'g');

// A label is written into the reply as markdown. A single line cannot introduce
// headings, lists or fences into a comment posted under someone else's name.
const MAX_LABEL_LENGTH = 200;
const MAX_DESCRIPTION_LENGTH = 500;

// A closed question offers a handful of choices. Far more than this is a degenerate
// payload, not a question, and would render as a wall of buttons. Mirrored by
// MAX_OPTIONS in ee/lib/ee/gitlab/work_items/duo_question.rb, so email drops the
// same payloads this does. Keep the two in sync.
const MAX_OPTIONS = 10;

const isNonEmptyString = (value) => typeof value === 'string' && value.trim().length > 0;

// The marker form carries labels only, so an id has to be derived from one. It has to
// survive a round trip through the answer marker, which stops at the first space: a
// label like "Entra ID" used verbatim never read back at all.
const toOptionId = (label) => {
  const id = String(label)
    .toLowerCase()
    .replace(/[^a-z0-9._-]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 64);

  // A label of "Rejected" would otherwise derive the reserved id and see the option
  // dropped, losing a choice the reader was meant to have.
  // eslint-disable-next-line @gitlab/require-i18n-strings -- an id fragment, never rendered
  return id === ANSWER_ID_CUSTOM ? `${id}-option` : id;
};

const isPlainObject = (value) =>
  typeof value === 'object' && value !== null && !Array.isArray(value);

const parseJson = (raw) => {
  try {
    return JSON.parse(raw);
  } catch {
    return null;
  }
};

// Mimics Zod's safeParse contract so a future swap to a real schema library is
// mechanical. `issues` travels with a success too, because an option can be
// dropped without making the whole question unusable.
const ok = (data, issues = []) => ({ success: true, data, issues });
const fail = (issues) => ({ success: false, issues });

const issue = (path, message) => ({ path, message });

/* eslint-disable @gitlab/require-i18n-strings -- diagnostics are for logs, never rendered */
const DIAGNOSTIC = {
  NOT_AN_OBJECT: 'not an object',
  REQUIRED: 'required',
  NO_USABLE_OPTIONS: 'closed question has no usable options',
  PAYLOAD_NOT_AN_OBJECT: 'not a JSON object',
  OPTIONS_NOT_AN_ARRAY: 'not a JSON array',
  MULTILINE_LABEL: 'must be a single line',
  TOO_LONG: 'exceeds the maximum length',
  TOO_MANY_OPTIONS: 'more options than can be rendered',
  RESERVED_ID: 'uses the id reserved for a typed answer',
  DUPLICATE_ID: 'duplicates an earlier option id',
};
/* eslint-enable @gitlab/require-i18n-strings */

/**
 * The option contract, declared once. Both payload shapes normalise into it.
 */
const validateOption = (raw, index) => {
  const at = (field) => `options[${index}].${field}`;

  if (!isPlainObject(raw)) return fail([issue(`options[${index}]`, DIAGNOSTIC.NOT_AN_OBJECT)]);

  const issues = [];
  if (!isNonEmptyString(raw.id)) issues.push(issue(at('id'), DIAGNOSTIC.REQUIRED));
  if (!isNonEmptyString(raw.label)) issues.push(issue(at('label'), DIAGNOSTIC.REQUIRED));
  if (issues.length) return fail(issues);

  // Picking an option that claims the reserved id would post the same marker a typed
  // answer does, leaving the two indistinguishable. Such an option is unusable, so it
  // is dropped like any other invalid one.
  if (raw.id === ANSWER_ID_CUSTOM) return fail([issue(at('id'), DIAGNOSTIC.RESERVED_ID)]);

  if (/[\r\n]/.test(raw.label)) return fail([issue(at('label'), DIAGNOSTIC.MULTILINE_LABEL)]);
  if (raw.label.length > MAX_LABEL_LENGTH) return fail([issue(at('label'), DIAGNOSTIC.TOO_LONG)]);

  const description = isNonEmptyString(raw.description) ? raw.description : '';

  return ok({
    id: raw.id,
    label: raw.label,
    description: description.slice(0, MAX_DESCRIPTION_LENGTH),
    recommended: raw.recommended === true,
  });
};

/**
 * The question contract. A closed question needs at least one usable option:
 * saying "closed" and offering nothing renderable is a corrupted payload, not
 * an open question, and the caller should hear about it.
 */
const validateQuestion = (raw) => {
  const wantsClosed = raw.type === QUESTION_TYPE_CLOSED;
  const issues = [];
  const options = [];

  // Only a closed question renders options, so an open one skips validating
  // them: reporting problems with options nobody will see is just noise.
  if (wantsClosed) {
    if (raw.options.length > MAX_OPTIONS) {
      return fail([issue('options', DIAGNOSTIC.TOO_MANY_OPTIONS)]);
    }

    const optionIds = new Set();

    raw.options.forEach((option, index) => {
      const result = validateOption(option, index);
      if (result.success) {
        if (optionIds.has(result.data.id)) {
          issues.push(issue(`options[${index}].id`, DIAGNOSTIC.DUPLICATE_ID));
        } else {
          optionIds.add(result.data.id);
          options.push(result.data);
        }
      } else {
        issues.push(...result.issues);
      }
    });

    if (options.length === 0) {
      return fail([issue('options', DIAGNOSTIC.NO_USABLE_OPTIONS), ...issues]);
    }
  }

  return ok(
    {
      type: wantsClosed ? QUESTION_TYPE_CLOSED : QUESTION_TYPE_OPEN,
      question: isNonEmptyString(raw.question) ? raw.question : '',
      multiple: wantsClosed && raw.multiple === true,
      options,
    },
    issues,
  );
};

/**
 * Adapters below only reshape what they find. Deciding whether it is valid is
 * the validator's job, so the rules live in one place. Each returns `null` when
 * its shape is absent from the body, and a failure when the shape is there but
 * cannot be read at all.
 */
const fenceToRaw = (text) => {
  const match = text.match(FENCE_RE);
  if (!match) return null;

  const payload = parseJson(match[1]);
  if (!isPlainObject(payload)) return fail([issue('payload', DIAGNOSTIC.PAYLOAD_NOT_AN_OBJECT)]);

  return ok({
    type: payload.type,
    question: payload.question,
    multiple: payload.multiple,
    options: Array.isArray(payload.options) ? payload.options : [],
  });
};

const markerToRaw = (text) => {
  const marker = text.match(MARKER_RE);
  if (!marker) return null;

  const content = marker[1];
  const labels = parseJson(content.match(MARKER_ARRAY_RE)?.[1]);
  if (!Array.isArray(labels)) return fail([issue('options', DIAGNOSTIC.OPTIONS_NOT_AN_ARRAY)]);

  // `duo:recommended` indexes the array as the flow wrote it, so the position
  // is assigned before any option can be dropped by validation.
  const recommendedIndex = Number(content.match(MARKER_RECOMMENDED_RE)?.[1] ?? 0) - 1;

  return ok({
    type: QUESTION_TYPE_CLOSED,
    question: '',
    multiple: /duo:multiple\b/.test(content),
    options: labels.map((label, index) => ({
      id: toOptionId(label),
      label,
      description: '',
      recommended: index === recommendedIndex,
    })),
  });
};

/**
 * @param {string} body Raw markdown body of a note.
 * @returns {{status: string, question?: Object, diagnostics?: Array}}
 */
export const parseDuoQuestion = (body = '') => {
  const text = String(body);
  const raw = fenceToRaw(text) ?? markerToRaw(text);

  if (!raw) return { status: PARSE_STATUS_NONE };
  if (!raw.success) return { status: PARSE_STATUS_INVALID, diagnostics: raw.issues };

  const result = validateQuestion(raw.data);

  return result.success
    ? { status: PARSE_STATUS_OK, question: result.data, diagnostics: result.issues }
    : { status: PARSE_STATUS_INVALID, diagnostics: result.issues };
};

/**
 * The reply carries the chosen option's label, because its readers are the next
 * model run and a human scrolling the thread. The id rides along in an HTML
 * comment so a reload can recover the choice without parsing prose.
 *
 * @param {{id: string, label: string}} option The option that was chosen.
 * @returns {string} Body for the reply that answers the question.
 */
export const buildDuoAnswer = ({ id, label }) => `${label}\n\n<!-- duo-answer: ${id} -->`;

/**
 * @param {string} body Raw markdown body of a reply.
 * @returns {?string} Id of the option it answered with, or null.
 */
export const parseDuoAnswer = (body = '') => String(body).match(ANSWER_MARKER_RE)?.[1] ?? null;

/**
 * A question that accepts several answers names each one as a bullet, so the next model
 * run reads them as a set rather than one run-on sentence, and records every id in a
 * single marker so a reload can tell which were picked.
 *
 * @param {Array<{id: string, label: string}>} selections The chosen options, in order.
 * @returns {string} Body for the reply that answers the question.
 */
export const buildDuoAnswers = (selections) => {
  const bullets = selections.map(({ label }) => `- ${label}`).join('\n');
  const ids = selections.map(({ id }) => id).join(',');

  return `${bullets}\n\n<!-- duo-answer: ${ids} -->`;
};

/**
 * The prose half of an answer reply, with every answer marker stripped so an id is
 * never rendered, and never read back in place of the one `buildDuoAnswer` appends.
 *
 * @param {string} body Raw markdown body of a reply.
 * @returns {string} The reply without its answer markers.
 */
export const stripDuoAnswerMarker = (body = '') =>
  String(body).replace(ANSWER_MARKER_ANYWHERE_RE, '').trim();

/**
 * The answers a reply carries, read back as the labels it names rather than by mapping
 * ids to options: an answer written in the reader's own words exists only in the body.
 *
 * @param {string} body Raw markdown body of a reply.
 * @returns {Array<string>} One entry per answer, in the order they were given.
 */
export const parseDuoAnswerLabels = (body = '') =>
  stripDuoAnswerMarker(body)
    .split('\n')
    .map((line) => line.replace(/^\s*-\s+/, '').trim())
    .filter(Boolean);
