# Default Template Validation

Quiper has a dev-only validation bridge for checking default engine selectors and action scripts against real chatbot pages.

## Safety Boundary

The bridge starts only when all of these are true:

- The bundle identifier is `app.sassanh.quiper.QuiperDev`.
- The app is launched with `--template-validation-server`.
- The server binds only to `127.0.0.1`.

Production Quiper refuses to start the bridge even if the flag is passed. The bridge has no endpoint for cookies, local storage, full DOM dumps, screenshots, or filesystem access. DOM probes return only bounded metadata such as counts, visibility, short accessible labels/text snippets, URL, title, and focused-element metadata.

## Interference UI suppression

Launching with `--template-validation-server` also suppresses chrome that would block lab work. This reuses `Constants.LaunchMode.shouldSuppressInterferenceUI` and does **not** redirect storage paths (unlike `--uitesting`):

- First-run onboarding wizard
- Ghost onboarding tip HUD
- Automatic update checks / update prompt windows
- Template-action-sync and sparse-bundle migration alerts at launch

You only need the validation flag; do not combine with `--uitesting` unless you intentionally want test storage isolation.

## Overlay hotkey fallback

While the primary global hotkey is still the default **Option+Space**, bridge mode also registers **Control+Space** as a show/hide fallback (same behavior as Xcode/DerivedData debug runs). Engine launch shortcuts are blocked from using Control+Space in that case so they do not collide.

## Run

Build and launch the Debug app with the validation flag:

```sh
xcodebuild -project Quiper.xcodeproj -scheme Quiper -configuration Debug -destination "platform=macOS,arch=arm64" -derivedDataPath /private/tmp/quiper-derived-data build
open /private/tmp/quiper-derived-data/Build/Products/Debug/Quiper.app --args --template-validation-server
```

Then run the validator:

```sh
node scripts/validate-default-templates.js
```

Useful options:

```sh
node scripts/validate-default-templates.js --engine Gemini --wait
node scripts/validate-default-templates.js --engine "Z.ai" --engine DeepSeek --reload
```

Use `--wait` when a provider needs manual login, CAPTCHA handling, or another human-visible unblock. The validator marks that engine as `needs-human` instead of broadening DOM access.

For provider-specific live checks, prefer checked-in scripts over ad hoc inline Node snippets. This keeps command approvals reusable and makes the validation work repeatable:

```sh
node scripts/validate-claude-template.js
node scripts/validate-x-template.js
node scripts/validate-zai-template.js
node scripts/validate-deepseek-template.js
node scripts/validate-openwebui-template.js
node scripts/validate-google-template.js
node scripts/validate-omlx-template.js
node scripts/validate-llamacpp-template.js
```

If a provider does not have a script yet, add one under `scripts/validate-<engine>-template.js` and keep it narrowly scoped:

- Select only the target engine through the bridge.
- Probe bounded visible controls, focus-selector matches, and action postconditions.
- Avoid opening private conversations or dumping full DOM content.
- Ask for human help when login, CAPTCHA, 2FA, or visual confirmation is faster or safer.

## Monthly Checklist

1. Build and launch QuiperDev with `--template-validation-server`.
2. Run `node scripts/audit-default-templates.js`.
3. Run the provider-specific validator for the engine being updated.
4. If a script changes, update the default value in `Quiper/Settings.swift`.
5. Apply the default into the running dev profile without restarting:

   ```sh
   node scripts/apply-default-template-to-dev-storage.js --service "Engine Name" --action "History"
   ```

6. Manually check the affected shortcuts in both small and large windows.
7. Re-run the provider validator and the static audit.

The live validators are safety rails, not a replacement for manual confirmation. Some responsive drawer controls, notably `llama.cpp` history/sidebar, can be easier to verify visually than to infer perfectly from DOM geometry.

## Applying Defaults Without Restarting

When a provider login is fragile, avoid restarting QuiperDev just to test an updated default script. Apply the repo default into the running dev profile's script storage:

```sh
node scripts/apply-default-template-to-dev-storage.js --service Gemini --action "New Session"
```

This updates `QuiperDev`'s saved action script files only. It does not affect production settings and does not restart the app or touch browser session data.

## Related Audit

Use the static audit before the live validation:

```sh
node scripts/audit-default-templates.js
node scripts/audit-default-templates.js --network
```

`--network` checks referenced provider URLs and can be noisy for providers that block automated requests. Treat network failures as prompts for human browser checks, not as permission to broaden DOM access.
