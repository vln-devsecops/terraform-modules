# aws/vlinder_auth live suite

Provider-backed coverage for `modules/aws/vlinder_auth`.

The suite:

- requests and validates an ACM certificate in `us-east-1` covering both
  hostnames the module derives (hosted UI and the bundled admin panel),
  using per-run randomized prefixes so it doesn't collide with concurrent
  runs or real usage of the shared delegated test domain
- applies the shared `aws/vlinder_auth` module
- verifies the user pool and hosted-UI domain are real and queryable, the
  admin panel/admin API outputs look like real HTTPS URLs, and the hosted-UI
  domain's Route53 alias records exist

## Environment

Set one of these variable pairs before running:

- `VLINDER_AUTH_TEST_BASE_DOMAIN` and `VLINDER_AUTH_TEST_ROUTE53_ZONE_ID`
- or reuse `MAIL_TEST_BASE_DOMAIN` and `MAIL_TEST_ROUTE53_ZONE_ID`

The second form is convenient when the shared delegated mail-test domain is
the only public delegated zone currently available in the `vln-devsecops`
AWS account.

## Known limitations of this suite

- It does not exercise the signup → verify → login → admin-panel flow
  end to end (that's what the BDD suite in `node-vlinder-auth`'s `e2e/`
  covers, against a real deployed stack, once vendored real Lambda/admin-panel
  source lands here instead of the current bootstrap placeholders).
- ACM DNS validation can take a few minutes; this suite is not fast.
