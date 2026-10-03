# W-FLASH — progress

Recorded by the lead from W-FLASH's final report (`Docs/Requests/W-FLASH.md`, REQ-W-FLASH-01): the agent kept the
record outside the repository because `check-ownership.sh` rejected `Docs/Progress/W-FLASH.md` at the time; the
script maps the path since f556cb5.

## Counts
- Feature IDs: **82** — 81 done, 1 not applicable, 0 remaining.
- Not applicable: FLASH-133 (DECISIONS 13: no screen-capture receive in v1).

## Notes
- Debug snapshots: `AA_FLASH_DEBUG_TAB=send|receive`, `AA_FLASH_DEBUG_AUTOSTART=1`; sheets `w-flash.review-changeset`,
  `w-flash.review-snapshot`, `w-flash.review-bare-snapshot`. Fixture folder `Tests/AACoreTests/Fixtures/ui/w-flash/`.
- The end-to-end apply test runs against W-PERSIST's real `DataStore.applySyncedData(_:)` now that it is merged.
