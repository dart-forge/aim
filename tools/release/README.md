# release

Release steps for aim.

    dart run release:bump 0.3.0                                # versions, member constraints, CHANGELOG "Unreleased" → 0.3.0, aim_cli template pins, docs version
    git commit -am "chore: bump version to 0.3.0" && git tag 0.3.0 && git push --tags
    dart run release:publish --dry-run && dart run release:publish   # dart pub publish, dependencies first, already-published versions skipped
    dart run release:create_release 0.3.0                      # GitHub release from the root CHANGELOG section

Tags have no `v` prefix (docs deploy and create_release expect `0.3.0`).
