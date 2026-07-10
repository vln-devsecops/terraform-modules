// Bootstrap placeholder -- see ../README.md. Cognito requires the trigger to
// return the event unchanged; this is otherwise a no-op pending real vendored
// code from node-vlinder-auth's packages/lambda-src/src/pre-token-generation.
exports.handler = async (event) => event;
