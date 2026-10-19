# Significant-energy applications

An optional dynamic reader queries `systemstats_get_top_coalitions` from the system library. This is a private interface and can change or be restricted. Missing symbols, nil results, invalid types and mismatched arrays show unavailable status.

The bounded selector sorts energy metrics, considers five candidates and applies a strict threshold: high/balanced/low sensitivity uses 10,000/20,000/35,000. Balanced is the default. CPU percentage is supplementary display, not the ranking metric; energy values are not watts. Only running GUI applications with valid CPU readings are shown, without backfilling omitted candidates.

Queries run off the main actor, coalesce overlapping requests and refresh at most every thirty seconds. Paused consumers discard pending results. CPU reads use a fixed command and a two-second limit. Application names and identifiers remain in memory and are excluded from history, backups and diagnostics.

Pure tests cover order, thresholds, candidate cap, stability and malformed data. `Scripts/test-energy.sh` provides a read-only interface/self-CPU smoke test. Native and x86_64 execution under existing Rosetta succeeded locally outside the restricted execution sandbox. That establishes local ABI execution, not a cross-OS support guarantee.
