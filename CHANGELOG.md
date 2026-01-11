# Changelog

## [0.8.2](https://github.com/ldonnez/memo/compare/v0.8.1...v0.8.2) (2026-01-11)


### Bug Fixes

* correct cleanup of tmp files when upgrading ([54f6a6b](https://github.com/ldonnez/memo/commit/54f6a6b609e8e84cba0377c38cf41539bca1044c))
* ensure cleanup of tmpdir ([372d3f2](https://github.com/ldonnez/memo/commit/372d3f2a3febc2add6728d3408a8d56476af22db))

## [0.8.1](https://github.com/ldonnez/memo/compare/v0.8.0...v0.8.1) (2026-01-11)


### Bug Fixes

* **init:** ensure .gpg files in subdirectories can be committed ([50bae3b](https://github.com/ldonnez/memo/commit/50bae3ba599b00e5fc34232421931192e98beb58))

## [0.8.0](https://github.com/ldonnez/memo/compare/v0.7.0...v0.8.0) (2025-12-30)


### ⚠ BREAKING CHANGES

* remove capture header functionality

### Features

* add .gitattributes to DEFAULT_IGNORE ([5d72a8e](https://github.com/ldonnez/memo/commit/5d72a8eac4fe7e6735ab7ba4f5ca3ca4a89d4382))
* add .githooks to DEFAULT_IGNORE ([4efebdc](https://github.com/ldonnez/memo/commit/4efebdc02cb28022f29fda51aed68b1a60c944a8))
* add memo init command ([48f333b](https://github.com/ldonnez/memo/commit/48f333b1c4bdc42fdf80b506d19f111b082377bd))
* allow memo encrypt to encrypt from stdin ([5e0a909](https://github.com/ldonnez/memo/commit/5e0a9096449f4e79d3a3e8fe0bdbd4f4c12b7619))
* only re-encrypt when changes are made using memo command ([d8a83a7](https://github.com/ldonnez/memo/commit/d8a83a75d6bcc74975af409ee5f0ff057008bb13))


### Bug Fixes

* always encrypt files with .gpg extension as output ([d167215](https://github.com/ldonnez/memo/commit/d1672156a52ee4ec6b5cac35f5a50404abe25030))
* continue when gpg recipients are not found ([067e581](https://github.com/ldonnez/memo/commit/067e581321c68f3fb62fca0c1bdb39217456a46e))
* don't delete file when decryption fails ([c4a7790](https://github.com/ldonnez/memo/commit/c4a7790c84f335b586e18873e86207bfe9b5ac4f))
* git-sync -&gt; sync ([3974b1f](https://github.com/ldonnez/memo/commit/3974b1f9541cb579751586047c9a3a98c286322c))


### Code Refactoring

* remove capture header functionality ([433c7ea](https://github.com/ldonnez/memo/commit/433c7ea2e187df1f28aeae069013b7b7264515b9))

## [0.7.0](https://github.com/ldonnez/memo/compare/v0.6.2...v0.7.0) (2025-12-23)


### Features

* add --force option to memo upgrade ([14753d3](https://github.com/ldonnez/memo/commit/14753d3ac470a4cfafa5b0ada55b42c566dd2630))

## [0.6.2](https://github.com/ldonnez/memo/compare/v0.6.1...v0.6.2) (2025-12-23)


### Bug Fixes

* allow files with gpg extension as CAPTURE_FILE ([6dfdef1](https://github.com/ldonnez/memo/commit/6dfdef1d7e6f0da57a85974e3f870834f4f40a81))

## [0.6.1](https://github.com/ldonnez/memo/compare/v0.6.0...v0.6.1) (2025-12-23)


### Bug Fixes

* remove unnecessary newline ([082ca58](https://github.com/ldonnez/memo/commit/082ca58c3f2fa15abf4505f5a5f2a85a416fcf1e))

## [0.6.0](https://github.com/ldonnez/memo/compare/v0.5.0...v0.6.0) (2025-12-23)


### Bug Fixes

* add --output via param instead of shell redirection ([db93bba](https://github.com/ldonnez/memo/commit/db93bba9e70006f284dcb25c774f9a1e2763aeef))
* add extra lines to ensure md compatibility ([1393f6c](https://github.com/ldonnez/memo/commit/1393f6cbdf6ba056d04f284d436723acf11532f2))
* turn off gpg compression ([8cc3fd4](https://github.com/ldonnez/memo/commit/8cc3fd487c9fa2b20de4b464cf78dfea4f305664))


### Code Refactoring

* rename DEFAULT_CAPTURE_HEADER -&gt; CAPTURE_HEADER ([c464620](https://github.com/ldonnez/memo/commit/c4646208677f21f58084830a803975faeb18c11b))

## [0.5.0](https://github.com/ldonnez/memo/compare/v0.4.0...v0.5.0) (2025-12-23)


### ⚠ BREAKING CHANGES

* memo git-sync -> memo sync git

### Features

* prepend default header when using memo without arguments ([368f52c](https://github.com/ldonnez/memo/commit/368f52ceb7638a6109f6baef769cbdfc40f00e4c))


### Code Refactoring

* memo git-sync -&gt; memo sync git ([e5a7e48](https://github.com/ldonnez/memo/commit/e5a7e4801801f0577c40a3e3511c01aec3cfaddc))

## [0.4.0](https://github.com/ldonnez/memo/compare/v0.3.0...v0.4.0) (2025-12-21)


### Features

* add memo git-sync command ([0725c64](https://github.com/ldonnez/memo/commit/0725c64039e5795866aa2ac7d4a47dcc6daf3d4a))

## [0.3.0](https://github.com/ldonnez/memo/compare/v0.2.3...v0.3.0) (2025-12-21)


### ⚠ BREAKING CHANGES

* cleanup API

### Code Refactoring

* cleanup API ([ad6cafb](https://github.com/ldonnez/memo/commit/ad6cafb6baae60ecf78ec04dac22c9c7be72eae0))

## [0.2.3](https://github.com/ldonnez/memo/compare/v0.2.2...v0.2.3) (2025-12-21)


### Bug Fixes

* ensure new line ([d60b345](https://github.com/ldonnez/memo/commit/d60b345725237e9da0ec363f59a2c15c348e3382))

## [0.2.2](https://github.com/ldonnez/memo/compare/v0.2.1...v0.2.2) (2025-12-21)


### Code Refactoring

* remove MEMO_NEOVIM_INTEGRATION flag ([cc307a8](https://github.com/ldonnez/memo/commit/cc307a850152d1ab5d10dd6fb5f629fc28163e24))

## [0.2.1](https://github.com/ldonnez/memo/compare/v0.2.0...v0.2.1) (2025-12-21)


### Bug Fixes

* **ci:** ensure checkout ([31d9f1a](https://github.com/ldonnez/memo/commit/31d9f1a2bd8a2755b65d2b3181832f9c035b7e91))

## [0.2.0](https://github.com/ldonnez/memo/compare/v0.1.3...v0.2.0) (2025-12-20)


### ⚠ BREAKING CHANGES

* remove cache_builder
* remove pinentry check

### Code Refactoring

* remove cache_builder ([77ee782](https://github.com/ldonnez/memo/commit/77ee782432687fef26a6a2c36c6c7d731c5731a9))
* remove pinentry check ([98124eb](https://github.com/ldonnez/memo/commit/98124eb127e10689107a735dfc94f33bde281ba9))

## [0.1.3](https://github.com/ldonnez/memo/compare/v0.1.2...v0.1.3) (2025-12-18)


### Bug Fixes

* don't resolve NOTES_DIR path ([3aea33b](https://github.com/ldonnez/memo/commit/3aea33bb495f3fbcd969b61cbfa287db8f9085cb))

## [0.1.2](https://github.com/ldonnez/memo/compare/v0.1.1...v0.1.2) (2025-09-21)


### Bug Fixes

* ensure correct version check with prefix ([8444258](https://github.com/ldonnez/memo/commit/8444258ad9780fbc128c5d21a807762fb66fcb1d))

## [0.1.1](https://github.com/ldonnez/memo/compare/v0.1.0...v0.1.1) (2025-09-21)


### Bug Fixes

* don't show error when no config file found ([83ba055](https://github.com/ldonnez/memo/commit/83ba0557271705823e5ef37d906cc639675ba8b3))

## [0.1.0](https://github.com/ldonnez/memo/compare/v0.0.1...v0.1.0) (2025-09-21)


### Features

* add release please ([1478ad3](https://github.com/ldonnez/memo/commit/1478ad3258077630fb6db9997079bbfc350ea754))
* always check if gpg password is cached ([2a60f0d](https://github.com/ldonnez/memo/commit/2a60f0d315e55201fbaf97a2be4e3612f476c8ad))
* don't pass empty keyids ([febddbf](https://github.com/ldonnez/memo/commit/febddbf3ae03a48a8d99012d5605ccf33beef737))
* ensure &lt;extension&gt;.gpg gets correctly checked ([9ef6b40](https://github.com/ldonnez/memo/commit/9ef6b40c0c36c8ce00d8904f18fb55e2555d0ae2))
* open DEFAULT_FILE when running memo ([8bcb22b](https://github.com/ldonnez/memo/commit/8bcb22bfb6ab5234c61b779280bc82ea40a737d3))


### Bug Fixes

* ensure default empty input ([5bd0f4d](https://github.com/ldonnez/memo/commit/5bd0f4da8e190d1c7034d4d667dd6edbf50b3409))
* pass local $input variable ([39cd6c5](https://github.com/ldonnez/memo/commit/39cd6c5c8fa3ac356d0aba3da4bc15fd9f3f4389))

## [0.2.0](https://github.com/ldonnez/memo/compare/v0.1.0...v0.2.0) (2025-09-03)


### Features

* add release-please ([6f8d133](https://github.com/ldonnez/memo/commit/6f8d133bb4ffb63e56c16f4ca56c80ac10cc8ddf))
* set correct version ([9956e16](https://github.com/ldonnez/memo/commit/9956e169394f161e4d8cc8a96969b8bc29c75514))
