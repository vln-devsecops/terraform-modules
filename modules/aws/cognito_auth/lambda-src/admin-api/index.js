// Bootstrap placeholder -- see ../README.md. Pending real vendored code from
// node-vlinder-auth's packages/lambda-src/src/admin-api.
exports.handler = async () => ({
  statusCode: 501,
  headers: { "content-type": "application/json" },
  body: JSON.stringify({ error: "not_yet_vendored" }),
});
