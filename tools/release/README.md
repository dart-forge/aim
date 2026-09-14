# release

Release steps for aim. Version bumping and publishing are done by rask; this package holds the aim-specific rest.

    rask bump 0.3.0                          # versions, member constraints, CHANGELOG "Unreleased" → 0.3.0
    dart run release:after_bump 0.3.0        # aim_cli scaffold template pins, docs version
    git commit -am "chore: bump version to 0.3.0" && git tag 0.3.0 && git push --tags
    rask publish --dry-run && rask publish   # dart pub publish, dependencies first, already-published versions skipped
    dart run release:create_release 0.3.0    # GitHub release from the root CHANGELOG section

Tags have no `v` prefix (docs deploy and create_release expect `0.3.0`).
