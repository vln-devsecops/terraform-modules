// Bootstrap placeholder -- see ../README.md. Cognito requires the trigger to
// return the event unchanged; this is otherwise a no-op pending real vendored
// code from node-vlinder-auth's packages/lambda-src/src/post-confirmation.
exports.handler = async (event) => event;
