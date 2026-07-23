# Version Ordering

Quiper uses `QuiperVersion` as its single version-ordering implementation for
software-update detection and version-aware settings migrations.

## Supported formats

The parser accepts the formats produced by the app and release workflow:

- Stable versions and tags: `1.2.3`, `v1.2.3`
- Suffixed app versions: `1.2.3-beta-nonproduction`, `1.2.3-whatever`
- Display versions with builds: `1.2.3-whatever (10)`
- Pre-release tags with builds: `beta-v1.2.3-10`, `nightly-v1.2.3-10`

An explicit build number from bundle or GitHub release metadata takes precedence
over a build number embedded in the version string.

## Ordering contract

Versions are compared in this order:

1. Numeric version components, from left to right. Missing trailing components
   are zero, so `1.2` equals `1.2.0`.
2. Suffix presence. For the same numeric version, every suffixed version is
   after the unsuffixed version.
3. Numeric build number. Within the same numeric version and suffix tier, a
   higher build is after a lower build. A present build is after a missing build.

Suffix labels deliberately share one ordering tier. Their text does not imply a
channel rank; build numbers order beta, nightly, and other non-production
variants of the same numeric version. If two different suffix labels have no
build metadata, their relative order is unknown instead of being guessed.

These examples follow directly from the contract:

```text
1.2.3-beta-nonproduction > 1.2.3
1.2.3-whatever > 1.2.3
1.2.3-whatever (10) > 1.2.3-whatever (9)
1.3.3 > 1.2.3
2.2.3 > 1.2.3
```

If a numeric version core cannot be parsed, comparison is unknown unless both
sides provide explicit build metadata. This keeps settings migrations
conservative while preserving update compatibility with legacy release tags.

See [Migration Architecture](migrations.md) for how this comparison determines
automatic, prompted, and deferred settings migrations.
