# release

Release steps for aim.

    dart run release:bump 0.3.0                                # versions, member constraints, CHANGELOG "Unreleased" → 0.3.0, aim_cli template pins, docs version
    git commit -am "chore: bump version to 0.3.0" && git tag 0.3.0 && git push --tags
    dart run release:publish --dry-run && dart run release:publish   # dart pub publish, dependencies first, already-published versions skipped
    dart run release:create_release 0.3.0                      # GitHub release from the root CHANGELOG section

Tags have no `v` prefix (docs deploy and create_release expect `0.3.0`).

`bump` updates `docs/.vitepress/config.mts`'s version constant and the
`aim_cli` scaffolding templates, but not the version numbers written as
plain text inside Markdown code samples under `docs/`. After bumping, grep
`docs/` for `\^\d+\.\d+\.\d+` and update any dependency example still
pinning the previous version (the Migration Guide's historical sections
are the intentional exception).

To hold a package back from a release, add `publish_to: none` to its pubspec.yaml. `bump` still updates its version and its `aim_*` constraints, so lockstep holds, but leaves its CHANGELOG alone. `publish` keeps it in the dependency graph for ordering but does not push it to pub.dev, and refuses to publish anything if a package that will be published depends on one that is held back. Remove the line to release it.
