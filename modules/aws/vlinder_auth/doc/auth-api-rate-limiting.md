# Auth API rate-limiting and threat-protection posture

## Why this exists

`local.auth_api_routes` (in `main.tf`) provisions seven unauthenticated
routes — `/auth/identify`, `/auth/password`, `/auth/signup`, `/auth/confirm`,
`/auth/resend`, `/auth/forgot`, `/auth/reset` — behind the `/api/v1/auth*`
CloudFront behavior. They're unauthenticated by design: this is how a client
obtains a session in the first place, so there's no token to check yet.
That also means they're the module's most exposed surface for credential
stuffing, user enumeration, and signup/email-send abuse, and until now the
only defenses were AWS's account-wide API Gateway defaults and Cognito's
per-user lockout — both incidental, neither sized for this specific surface.
This document is the writeup for what's now enforced, what it doesn't cover,
and what to add if the gap it leaves open ever needs closing.

## What's enforced automatically

1. **Per-route API Gateway throttling**, via `var.auth_api_throttling`
   (defaults: `burst_limit = 10`, `rate_limit = 5`), wired into
   `local.auth_api_routes` and applied by the `http_api` module as a
   `route_settings` block on the stage. Two different units, worth being
   precise about:
   - `burst_limit` is a token-bucket **capacity** — a count of requests that
     may land instantaneously, not a rate.
   - `rate_limit` is the steady-state refill rate, in **requests per
     second**.

   With the defaults: up to 10 requests can land at once, then traffic to
   that route is capped to 5 req/s sustained. This is an **aggregate** limit
   — shared across every caller of the route, not tracked per source IP —
   and it's caller-tunable via `auth_api_throttling` since the right numbers
   depend on expected legitimate traffic.
2. **Cognito `advanced_security_mode`** (`var.advanced_security_mode`,
   default `OFF`): compromised-credential checks and adaptive
   (risk-based) authentication. Set to `AUDIT` to start logging risk signals
   without changing sign-in behavior, or `ENFORCED` to also challenge/block
   high-risk sign-ins. Defaults to `OFF` rather than being turned on
   automatically — see **Cost implications** below for why.
3. **Cognito's existing per-user lockout**, unchanged by this module and
   already in place before this document existed.

## What's explicitly not covered

**Per-source-IP rate limiting.** API Gateway route throttling (item 1 above)
is a shared, aggregate token bucket for the whole route — it protects the
route's overall capacity and cost, but a single attacker hammering
`/auth/signup` consumes the same shared budget as everyone else, and a slow,
distributed credential-stuffing attempt (many IPs, low rate per IP) will
often stay under the aggregate threshold entirely.

## Recommendation: WAF rate-based rules via `waf_web_acl_arn`

For per-IP protection, associate a WAFv2 web ACL with a rate-based rule
scoped to the `/api/v1/auth*` path pattern, via the module's existing
`waf_web_acl_arn` variable (already wired to
`aws_cloudfront_distribution.auth_site`). This is the *only* per-IP
enforcement point available here: WAFv2 web ACLs cannot associate directly
with an API Gateway v2 HTTP API (the `http_api` module) — only with
CloudFront, ALB, API Gateway REST APIs, AppSync, and Cognito user pools — so
the CloudFront edge in front of both the auth and admin APIs is the only
attachment point that actually sits in front of these routes.
`waf_web_acl_arn` is not set by this module by default (see **Cost
implications**), so this is left as a recommendation for callers to adopt
based on their own risk tolerance and budget, not something the module
enables on its own.

## Cost implications

All figures below are current as of the time of writing — confirm against
the linked AWS pricing pages before relying on them for a budget decision.

- **API Gateway route throttling** (`auth_api_throttling`): no separate
  charge. It's a token-bucket limit on request submissions, not a billed
  feature, and can only ever *reduce* the request volume you're billed for.
  This is why it's the module's enabled-by-default option. Ref: [API Gateway
  request throttling](https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-request-throttling.html).
- **Cognito `advanced_security_mode`** (threat protection): setting it to
  anything other than the default `OFF` — i.e. opting into `AUDIT` or
  `ENFORCED` — requires the user pool to be on the **Plus feature plan**, or
  on the **Lite** plan with threat protection purchased as a paid add-on.
  It's billed per Monthly Active User (MAU) on a tiered schedule (first 50k
  MAU / next 50k MAU / beyond 100k MAU, at decreasing per-MAU rates), and
  critically, **the rate is the same whether the mode is `AUDIT` or
  `ENFORCED`** — you're paying for the feature plan/tier, not for the
  enforcement mode. This is why the module defaults to `OFF` rather than the
  `AUDIT` a reviewer might otherwise expect as a "free" middle ground: it
  isn't free. Refs: [Threat protection developer
  guide](https://docs.aws.amazon.com/cognito/latest/developerguide/cognito-user-pool-settings-advanced-security.html),
  [Amazon Cognito pricing](https://aws.amazon.com/cognito/pricing/).
- **AWS WAF** (the `waf_web_acl_arn` recommendation above): a flat monthly
  cost per web ACL, a flat monthly cost per rule (including a rate-based
  rule), plus a per-million-requests-processed charge, all prorated hourly
  with no upfront commitment. Ref: [AWS WAF
  pricing](https://aws.amazon.com/waf/pricing/).

## If stronger enforcement is ever needed

Turning on `advanced_security_mode = "ENFORCED"` and/or setting
`waf_web_acl_arn` with an auth-scoped rate-based rule are both
caller-configurable today — no module change required, just variable
overrides once the cost is budgeted for. If a need arises that isn't covered
by either (e.g. per-IP throttling without WAF, or a CAPTCHA challenge on
repeated failures), treat that as a new design question rather than
retrofitting it here speculatively: build it when there's an actual caller
for it, using the layering above as the starting point.
