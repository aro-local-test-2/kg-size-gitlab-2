import { uniqueId } from 'lodash-es';
import { readFileAsDataURL } from '~/lib/utils/file_utility';
import { numberToHumanSize } from '~/lib/utils/number_utils';
import { s__, sprintf } from '~/locale';

/**
 * Attachment support for Duo Agentic Chat.
 *
 * Files are sent to the flow service as `additional_context` entries rather than over a
 * dedicated binary channel, because `AdditionalContext` is four string fields and
 * `StartWorkflowRequest` has no bytes field. Each file becomes one entry whose `content` is
 * a JSON document holding the base64 payload.
 *
 * The limits below intentionally mirror the flow service
 * (`duo_workflow_service/entities/attachments.py`). It re-validates everything and rejects
 * the whole turn when a file falls outside its bounds, so a looser limit here would cost the
 * user their message instead of the per-file warning we show.
 */
export const ATTACHMENTS_CATEGORY = 'attachments';

export const MAX_ATTACHMENTS = 5;
export const MAX_ATTACHMENT_BYTES = 2 * 1024 * 1024;
// Spelled as a product rather than 2_500_000: babel leaves numeric separators intact and
// the webpack 4 parser cannot read them, which fails the asset build.
export const MAX_TOTAL_ATTACHMENT_BYTES = 2.5 * 1000 * 1000;

// The intersection of what every provider the flow service routes to accepts
// (Anthropic, Gemini, Vertex AI, OpenAI, Bedrock). GIF is excluded because Gemini and
// Vertex do not take it, and HEIC/HEIF because only they do.
//
// This must not be looser than the service's own list: it rejects the turn as a whole,
// so a type accepted here and refused there costs the user their message, rather than
// the per-file warning they get below.
export const ALLOWED_IMAGE_MIME_TYPES = ['image/png', 'image/jpeg', 'image/webp'];

const i18n = {
  UNSUPPORTED_TYPE: s__(
    'DuoAgenticChat|%{filename} was not attached. Only PNG, JPEG, and WebP images are supported.',
  ),
  TOO_LARGE: s__(
    'DuoAgenticChat|%{filename} was not attached. Images must be %{limit} or smaller.',
  ),
  TOO_MANY: s__(
    'DuoAgenticChat|You can attach up to %{max} images per message. Some images were not attached.',
  ),
  TOTAL_TOO_LARGE: s__(
    'DuoAgenticChat|%{filename} was not attached. Attachments must total %{limit} or less.',
  ),
  READ_FAILED: s__('DuoAgenticChat|%{filename} could not be read and was not attached.'),
};

const BASE64_DATA_URL_PREFIX = /^data:[^;,]*;base64,/;

/**
 * Strips the `data:<mime>;base64,` prefix that FileReader produces, leaving bare base64.
 *
 * @param {String} dataUrl
 * @returns {String|null} base64 payload, or null when the URL is not base64-encoded
 */
const base64FromDataUrl = (dataUrl) => {
  if (typeof dataUrl !== 'string' || !BASE64_DATA_URL_PREFIX.test(dataUrl)) return null;

  return dataUrl.replace(BASE64_DATA_URL_PREFIX, '') || null;
};

export const isSupportedAttachmentType = (file) => ALLOWED_IMAGE_MIME_TYPES.includes(file?.type);

/**
 * Reads a File into the shape the flow service expects.
 *
 * `previewUrl` is the full data URL and is kept for local rendering only — it is never sent.
 *
 * @param {File} file
 * @returns {Promise<Object|null>} attachment, or null when the file could not be read
 */
export const readFileAsAttachment = async (file) => {
  const dataUrl = await readFileAsDataURL(file);
  const data = base64FromDataUrl(dataUrl);

  if (!data) return null;

  return {
    id: uniqueId('duo-chat-attachment-'),
    filename: file.name,
    mimeType: file.type,
    byteSize: file.size,
    data,
    previewUrl: dataUrl,
  };
};

/**
 * Validates and reads a batch of files against the already-attached set.
 *
 * Rejections are per-file and accumulate rather than aborting the batch, so dropping ten
 * files where one is a PDF still attaches the other nine.
 *
 * @param {Object} options
 * @param {File[]} options.files incoming files
 * @param {Object[]} options.existing already-attached attachments
 * @returns {Promise<{ attachments: Object[], errors: String[] }>}
 */
export const buildAttachments = async ({ files = [], existing = [] } = {}) => {
  const errors = [];
  const accepted = [];

  let remainingSlots = MAX_ATTACHMENTS - existing.length;
  let totalBytes = existing.reduce((sum, item) => sum + item.byteSize, 0);

  let droppedForCount = false;

  // Sequential rather than Promise.all: each decision depends on the running totals of the
  // files accepted before it, so the cumulative checks have to be ordered.
  for (const file of files) {
    if (remainingSlots <= 0) {
      droppedForCount = true;
      continue;
    }

    if (!isSupportedAttachmentType(file)) {
      errors.push(sprintf(i18n.UNSUPPORTED_TYPE, { filename: file.name }));
      continue;
    }

    if (file.size > MAX_ATTACHMENT_BYTES) {
      errors.push(
        sprintf(i18n.TOO_LARGE, {
          filename: file.name,
          limit: numberToHumanSize(MAX_ATTACHMENT_BYTES),
        }),
      );
      continue;
    }

    if (totalBytes + file.size > MAX_TOTAL_ATTACHMENT_BYTES) {
      errors.push(
        sprintf(i18n.TOTAL_TOO_LARGE, {
          filename: file.name,
          limit: numberToHumanSize(MAX_TOTAL_ATTACHMENT_BYTES),
        }),
      );
      continue;
    }

    let attachment;

    try {
      // eslint-disable-next-line no-await-in-loop
      attachment = await readFileAsAttachment(file);
    } catch {
      // A read that fails rejects only this file. Letting it escape would take the
      // whole batch with it, discarding files already accepted above.
      attachment = null;
    }

    if (!attachment) {
      errors.push(sprintf(i18n.READ_FAILED, { filename: file.name }));
      continue;
    }

    accepted.push(attachment);
    totalBytes += attachment.byteSize;
    remainingSlots -= 1;
  }

  if (droppedForCount) {
    errors.push(sprintf(i18n.TOO_MANY, { max: MAX_ATTACHMENTS }));
  }

  return { attachments: accepted, errors };
};

/**
 * Converts attachments into `additional_context` entries for the start request.
 *
 * One entry per file, matching how the flow service parses the category.
 *
 * @param {Object[]} attachments
 * @returns {Object[]} additional_context entries
 */
export const buildAttachmentContext = (attachments = []) =>
  attachments.map((attachment) => ({
    category: ATTACHMENTS_CATEGORY,
    content: JSON.stringify({
      mime_type: attachment.mimeType,
      data: attachment.data,
      filename: attachment.filename,
    }),
    metadata: '{}',
  }));

/**
 * Extracts files from a drag or paste event payload.
 *
 * Unsupported types are deliberately kept rather than filtered out, so that
 * `buildAttachments` reports them the same way it reports a file chosen from the picker.
 * Dropping a PDF should say so, not do nothing.
 *
 * Pasted screenshots arrive as `DataTransferItem`s with an empty `name`, so a synthetic
 * filename is generated for them.
 *
 * @param {DataTransfer} dataTransfer
 * @returns {File[]}
 */
export const filesFromDataTransfer = (dataTransfer) => {
  if (!dataTransfer) return [];

  return Array.from(dataTransfer.files || []).map((file) => {
    if (file.name) return file;

    const extension = file.type.split('/')[1] || 'png';
    return new File([file], `image-${Date.now()}.${extension}`, { type: file.type });
  });
};

/**
 * True when a drag event is carrying files, as opposed to selected text or a link.
 *
 * @param {DragEvent} event
 * @returns {Boolean}
 */
export const isFileDrag = (event) => Array.from(event?.dataTransfer?.types || []).includes('Files');
