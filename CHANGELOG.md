# Changelog

## [1.2.0](https://github.com/vln-devsecops/terraform-modules/compare/v1.1.0...v1.2.0) (2026-09-01)


### Features

* **static_site:** add first-class enable_noindex parameter ([#252](https://github.com/vln-devsecops/terraform-modules/issues/252)) ([24867a1](https://github.com/vln-devsecops/terraform-modules/commit/24867a1486a1cc02732bfcfced09d4db708e77f7))


### Bug Fixes

* **static_site:** add pretty_url_exceptions to protect extensionless static files ([#250](https://github.com/vln-devsecops/terraform-modules/issues/250)) ([d786cd9](https://github.com/vln-devsecops/terraform-modules/commit/d786cd988786d30325d0bb52c354f3803acf0ff7))

## [1.1.0](https://github.com/vln-devsecops/terraform-modules/compare/v1.0.0...v1.1.0) (2026-08-24)


### Features

* **http_api:** support a Lambda REQUEST authorizer (CUSTOM routes) ([f1447e5](https://github.com/vln-devsecops/terraform-modules/commit/f1447e52658e894c1aea54c900f735e8261cda94))

## [1.0.0](https://github.com/vln-devsecops/terraform-modules/compare/v0.19.1...v1.0.0) (2026-08-21)


### Features

* **http_api:** support per-route AWS_IAM authorization ([#175](https://github.com/vln-devsecops/terraform-modules/issues/175)) ([4636fb3](https://github.com/vln-devsecops/terraform-modules/commit/4636fb3ee666fb7dc0f0d767c646895a505661cf))


### Bug Fixes

* adopt canonical hardened automerge template from guidance ([#177](https://github.com/vln-devsecops/terraform-modules/issues/177)) ([28dd76a](https://github.com/vln-devsecops/terraform-modules/commit/28dd76ae647f3489f1675a19fa5eb30afc275bc0))
* **ci:** sync ci_dependabot_automerge.yml, merge directly instead of --auto ([#205](https://github.com/vln-devsecops/terraform-modules/issues/205)) ([eb50b75](https://github.com/vln-devsecops/terraform-modules/commit/eb50b7572e866513a41a1b91ad944ea557efba5c))
* **contact_form:** add random per-stack suffix to fixed resource names ([#174](https://github.com/vln-devsecops/terraform-modules/issues/174)) ([d29b0cd](https://github.com/vln-devsecops/terraform-modules/commit/d29b0cdd9181c5e48206359ca55bbfccda340a5b))
* dynamodb: replace deprecated GSI hash_key/range_key with key_schema ([#159](https://github.com/vln-devsecops/terraform-modules/issues/159)) ([b03931d](https://github.com/vln-devsecops/terraform-modules/commit/b03931d0f14f7bd4edb6c46dd1e6c9282e93a617))
* github_oidc README examples reference a tag that predates the module ([#193](https://github.com/vln-devsecops/terraform-modules/issues/193)) ([31d1a28](https://github.com/vln-devsecops/terraform-modules/commit/31d1a2883a67e5c234257829c8fe87cf44b4ab47))
* resync ci_dependabot_automerge.yml with guidance@main ([#191](https://github.com/vln-devsecops/terraform-modules/issues/191)) ([#192](https://github.com/vln-devsecops/terraform-modules/issues/192)) ([4f9a7a3](https://github.com/vln-devsecops/terraform-modules/commit/4f9a7a31023b60c60c758dbc24809d5be7b4dadd))
* **static_site:** create_before_destroy for CloudFront viewer-request function ([#220](https://github.com/vln-devsecops/terraform-modules/issues/220)) ([bc68b95](https://github.com/vln-devsecops/terraform-modules/commit/bc68b95de7c6f9253b52be4d7a953591da8cec4f))


### Documentation

* mention release-please in README; fix Release-As footer ([eb56d55](https://github.com/vln-devsecops/terraform-modules/commit/eb56d55eed7fd3319fabbfb249efe383d3e839b0))
