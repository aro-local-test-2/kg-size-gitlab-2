import { messageWidgets } from './message_widgets';
import { messageTransformers } from './message_transformers';
import { slashCommands } from './slash_commands';

export { messageWidgets, messageTransformers, slashCommands };

// Every capability the registry recognises. A plugin field not listed here is
// rejected at registration time rather than silently ignored, i.e `messageWidget`
// (singular) is caught instead of quietly rendering nothing.
export const CAPABILITIES = [messageWidgets, messageTransformers, slashCommands];
