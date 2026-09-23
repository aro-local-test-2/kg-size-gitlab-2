/* eslint-disable import/no-commonjs */
const { TextDecoder, TextEncoder } = require('node:util');

global.TextDecoder = TextDecoder;
global.TextEncoder = TextEncoder;

// `msw/node` reads these globals while its module body evaluates, which is before any
// `setupFilesAfterEnv` file runs, so they cannot be assigned from `test_setup.js`.
// `require` keeps this load after the TextEncoder assignment above, which
// `@whatwg-node/fetch` needs at its own module load time.
const { ReadableStream, TransformStream, WritableStream } = require('node:stream/web');
const { BroadcastChannel } = require('node:worker_threads');
const { fetch, Request, Response, Headers } = require('@whatwg-node/fetch');

global.fetch = fetch;
global.Request = Request;
global.Response = Response;
global.Headers = Headers;
global.ReadableStream = ReadableStream;
global.TransformStream = TransformStream;
global.WritableStream = WritableStream;
global.BroadcastChannel = BroadcastChannel;
