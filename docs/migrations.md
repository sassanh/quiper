# Migration Architecture

Quiper has two migration families. Choosing the correct family is part of the
migration contract:

1. **Persisted-settings migrations** use `PersistedSettingsMigrationContext`
   when app-version compatibility determines whether Quiper may rewrite a
   settings payload.
2. **Artifact migrations** use authoritative filesystem or format evidence when
   the artifact itself determines eligibility. An app version is not a
   substitute for checking that evidence.

## Persisted-settings pattern

All version-aware settings migrations share the ordering implemented by
`QuiperVersion`. Create one `PersistedSettingsMigrationContext` for the decoded
payload, then keep these stages separate:

1. **Detection** inspects a legacy key or another authoritative schema marker.
2. **Eligibility** asks the context for a disposition. Do not compare version
   strings in individual migrations.
3. **Transformation** changes the in-memory current-schema model.
4. **Presentation** either runs automatically or waits for the user to resolve
   a prompt.
5. **Persistence** emits the current schema only after the migration is
   eligible and resolved.

The shared dispositions are:

| Disposition | Meaning |
| --- | --- |
| `notNeeded` | The migration's structural predicate was not detected. |
| `deferred` | It was detected, but the source is newer or its version cannot be compared safely. |
| `runAutomatically` | The source is compatible and the automatic transformation may be persisted. |
| `awaitingPrompt` | The source is compatible and persistence waits for the user's choice. |

An existing unversioned payload is treated as legacy. A versioned payload is
eligible only when its version is equal to or before the running app according
to [Version Ordering](version-ordering.md). Newer and unparseable versions are
conservative: their migrations are deferred, unresolved fields stay omitted,
and their original `quiperVersion` is preserved during unrelated saves.

The migration identifier and disposition map in `Settings` replace independent
prompt and suppression flags. A prompted migration resolves by applying the
choice, clearing its disposition, and saving once. An automatic migration saves
only when its disposition is `runAutomatically`.

## Current inventory

### Version-aware persisted settings

| Migration | Detection | Presentation | Persistence |
| --- | --- | --- | --- |
| Template action-script sync | Existing unversioned settings plus a matching bundled template/action candidate | Prompt | Keeps `quiperVersion` absent until resolved, then writes the current version |
| Engine-shortcut toggle | Existing settings with the preference key absent | Prompt | Keeps the key absent until resolved; future or unknown source versions defer without prompting |
| Independent selector display modes | Legacy shared `selectorDisplayMode` decoded into both current fields | Automatic | Rewrites only for an eligible source and never encodes the obsolete shared key |

### Decoder-boundary compatibility

Some representations are transformed solely because a legacy key is present:

- Update beta/nightly booleans to `UpdateChannel`
- `"Blur Effect"` to the current window background mode
- Flat window appearance settings to light/dark theme settings
- Associated/friend domains to ordered routing rules
- `autoLockPolicy` to the current lock booleans
- Prompt-recording glow to the current indicator style

These transformations belong in their type's decoder. The in-memory model and
encoder remain current-schema only. They do not independently request an
immediate save, so they do not need a release-version predicate.

### Artifact-driven migrations

These migrations deliberately do not use `QuiperVersion`:

- The Application Support directory move runs before settings are loaded and
  checks that the legacy directory exists while the destination does not.
- The WebKit onboarding wizard checks the old and new WebsiteData locations.
- The legacy hotkey import checks the separate legacy hotkey file.
- Sparse-bundle migration checks encryption state, bundle existence, and the
  recorded on-disk format; both the launch prompt and per-engine prompt use
  those facts.
- Securing or unsecuring an engine is a user-requested storage transition, not
  a release migration.

For these cases, adding an app-version cutoff would be weaker than the existing
artifact predicate and could skip valid work or repeat completed work.

## Adding a migration

- Establish the old representation and release boundary from repository
  evidence; do not infer them from a field name.
- Add a `PersistedSettingsMigration` identifier only when settings-version
  compatibility is authoritative.
- Express detection as a structural predicate and obtain the disposition from
  the existing context.
- Keep prompt state represented by the disposition rather than adding a new
  boolean and persistence-suppression flag.
- Preserve legacy fields while a prompted migration is unresolved.
- Make the transformation deterministic, lossless, and idempotent.
- Test compatible, unversioned, newer, and unparseable versions as applicable;
  test prompt resolution or automatic persistence separately.
- Verify current-schema encoding omits obsolete keys and repeated reads do not
  migrate again.
