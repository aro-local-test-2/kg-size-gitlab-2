import { TOOL_NAME_CLARIFICATION_QUESTION } from '../constants';
import { isUserMessage } from '../utils/messages_utils';

const parseAnswerContent = (content) => {
  try {
    return JSON.parse(content);
  } catch {
    return null;
  }
};

const createSkippedResponse = () => ({ chosenOptionId: 'skipped', answerMsg: null });

const createAnswerResponse = (answerMsg, chosenOptionId) => ({ answerMsg, chosenOptionId });

const findAnswerMessage = (messagesAfter, toolMessageId) => {
  const response = { chosenOptionId: null, answerMsg: null };

  const userMessages = messagesAfter.filter(isUserMessage);

  if (!userMessages.length) return response;

  const answerMsg = userMessages.find(
    (msg) => parseAnswerContent(msg.content)?.message_id === toolMessageId,
  );

  if (!answerMsg) return createSkippedResponse();

  const parsed = parseAnswerContent(answerMsg.content);

  if (!parsed) return createSkippedResponse();

  return createAnswerResponse(answerMsg, parsed.selected_option);
};

export const clarificationQuestionTransformer = (messages) => {
  const skippedMessages = new Set();

  return messages.reduce((result, msg, index) => {
    let modifiedMsg = msg;

    if (skippedMessages.has(msg)) {
      return result;
    }

    if (msg.tool_info?.name === TOOL_NAME_CLARIFICATION_QUESTION) {
      const { answerMsg, chosenOptionId } = findAnswerMessage(
        messages.slice(index + 1),
        msg.message_id,
      );

      if (answerMsg) {
        skippedMessages.add(answerMsg);
      }

      modifiedMsg = {
        ...msg,
        tool_info: {
          ...msg.tool_info,
          args: {
            ...msg.tool_info.args,
            chosen_option_id: chosenOptionId,
          },
        },
      };
    }

    result.push(modifiedMsg);

    return result;
  }, []);
};
