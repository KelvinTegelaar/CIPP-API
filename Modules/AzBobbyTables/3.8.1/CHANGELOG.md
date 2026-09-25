# Changelog for the module

The format is based on and uses the types of changes according to [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- `Remove-AzDataTableLargeEntity`, and the stale part cleanup of `Add-` and `Update-AzDataTableLargeEntity`, no longer scan the whole partition to find part rows. Part rows were looked up by filtering on `OriginalEntityId`, which is not a key, so every lookup read every row in the partition and removing entities from large partitions took minutes per batch. Part rows are now found by their RowKey range, an index seek, and confirmed by `OriginalEntityId`.

## [3.8.1] - 2026-09-18

### Added

- Added managed identity authentication support for Azure Arc-enabled servers.

### Changed

- `Get-AzDataTableLargeEntity` now streams unbounded, unsorted reads instead of creating the whole list before returning, improving performance and reducing memory usage in most cases. Reads that use `-First`, `-Skip` or `-Sort` keep the previous behaviour.

## [3.8.0] - 2026-08-18

### Added

- Added `Update-AzDataTableLargeEntity` for updating entities that exceed the Azure Table Storage size limits, allowing for updates of entities added by `Add-AzDataTableLargeEntity`.

### Fixed

- `Update-AzDataTableEntity` no longer creates entities that do not exist when called with `-Force` or with entities that carry no ETag.

## [3.7.1] - 2026-08-12

### Changed

- `Get-AzDataTableLargeEntity` no longer fails an entire query when one entity cannot be reassembled. It skips that entity and reports it as a non-terminating error. Use `-ErrorAction Stop` for the previous behavior.

## [3.7.0] - 2026-08-10

### Added

- Added `Add-AzDataTableLargeEntity`, `Get-AzDataTableLargeEntity` and `Remove-AzDataTableLargeEntity` for working with entities that exceed Azure Table Storage size limits (64 KiB per string property, 1 MiB per entity):
  - `Add-AzDataTableLargeEntity` chunks oversized string properties, splits entities that exceed row limits across multiple rows, and records `PartCount` metadata on each part row.
  - `Get-AzDataTableLargeEntity` reassembles multipart entities (even when only some rows match the filter) and raises `IncompleteEntityException` if any rows or split-property chunks are missing.
  - `Remove-AzDataTableLargeEntity` removes all rows that belong to a multipart entity.

### Changed

- Added automatic clamping of `Get-AzDataTableEntity -First` page-size hints to Azure Table Storage's maximum of 1000, preventing `400 InvalidInput` for larger values.

## [3.6.1] - 2026-07-29

### Changed

- `Add-`, `Remove-` and `Update-AzDataTableEntity` now collect entities from the pipeline and submit them as batched transactions when the pipeline completes, instead of one transaction per pipeline record.
- `Get-AzDataTableEntity` passes a page-size hint to the service when `-First` is used without `-Sort`, so the service returns a bounded page instead of a full page truncated client-side.
- `-Count` no longer projects full PSObjects in order to count them.
- Entity validation and converter selection now run in a single pass.

### Removed

- Dependency on `System.Linq.Async`; queries now run synchronously.

## [3.6.0] - 2026-07-01

### Added

- Added a `-MaxConnectionsPerServer` parameter to `New-AzDataTableContext` to cap the number of concurrent connections per server endpoint on the shared HTTP client pool. Applied process-wide on first use; default is unlimited. ([#133](https://github.com/PalmEmanuel/AzBobbyTables/pull/122))
- Added a `-MaxRetries` parameter to the table operation cmdlets (`Add-`, `Get-`, `Remove-`, `Update-AzDataTableEntity`, `Clear-`, `Get-`, `New-`, `Remove-AzDataTable`) to retry throttled requests (HTTP 429), waiting for the service's Retry-After hint between attempts. Defaults to `0` (no retries). ([#133](https://github.com/PalmEmanuel/AzBobbyTables/pull/122))

### Changed

Bumped Microsoft.VisualStudio.Threading from 17.14.15 to 18.7.23 (#132)

## [3.5.0] - 2026-04-20

### Changed

- Now shares a single HttpClient across all TableClient/TableServiceClient instances via HttpClientTransport, enabling TCP connection pooling and reducing socket churn in high-concurrency scenarios [#122](https://github.com/PalmEmanuel/AzBobbyTables/pull/122)
- Bump System.Linq.Async from 7.0.0 to 7.0.1

## [3.4.2] - 2026-03-30

### Fixed

- Support Managed Identity on Azure VMs via IMDS fallback ([#116](https://github.com/PalmEmanuel/AzBobbyTables/pull/116))

### Changed

- Updated documentation to include `SortedList` as a supported entity type for `Add-`, `Update-`, and `Remove-AzDataTableEntity` ([#117](https://github.com/PalmEmanuel/AzBobbyTables/pull/117))

## [3.4.1] - 2026-03-05

### Changed

- Bump System.Linq.Async from 6.0.3 to 7.0.0
- Improved error handling to respect -ErrorAction through WriteError

## [3.4.0] - 2025-07-03

### Added

- Added SortedList as valid type for -Entity parameter [#52](https://github.com/PalmEmanuel/AzBobbyTables/issues/52)
- New command `Get-AzDataTableSupportedEntityType` to get the supported data types for the module when using `-Entity` parameter

### Changed

- Dependency version bumps
- Rewrote core module logic to add a converter system which allows for flexible entity types
- Updated gitversion config for build and release
- Improved module tests for the new type converter system

## [3.3.2] - 2025-02-26

### Fixed

- Fixed bug where validation for Partition- and RowKey was not checking case sensitivity [#68](https://github.com/PalmEmanuel/AzBobbyTables/pull/81)

## [3.3.1] - 2024-10-19

### Added

- Added `-OperationType` parameter to `Add-AzDataTableEntity` and `Update-AzDataTableEntity` to support merge or replace operations [#81](https://github.com/PalmEmanuel/AzBobbyTables/pull/81)

## [3.3.0] - 2024-10-18

### Added

- Added command `Get-AzDataTable` to get the names of tables in a storage account [#77](https://github.com/PalmEmanuel/AzBobbyTables/issues/77)

### Changed

- Implemented TableServiceClient to support operations on tables in the storage account.

## [3.2.1] - 2024-07-09

### Fixed

- Fixed bug where empty lines were written to console.

## [3.2.0] - 2024-03-21

### Added

- ETag validation for Update- & Remove-AzDataTableEntity ([#58](https://github.com/PalmEmanuel/AzBobbyTables/issues/58))

### Fixed

- Missing examples of Remove-AzDataTableEntity ([#62](https://github.com/PalmEmanuel/AzBobbyTables/issues/62))

## [3.1.3] - 2024-01-20

### Added

- Added Sampler ([#48](https://github.com/PalmEmanuel/AzBobbyTables/issues/48)).
- Added support for user-assigned managed identities ([#54](https://github.com/PalmEmanuel/AzBobbyTables/issues/54)).

## [3.1.2] - 2024-01-05

### Added

- Help documentation for a DateTime problem caused by the SDK (#43).

## 3.1.1 - 2023-05-03

[unreleased]: https://github.com/PalmEmanuel/AzBobbyTables/compare/v3.8.1...HEAD
[3.8.1]: https://github.com/PalmEmanuel/AzBobbyTables/compare/v3.8.0...v3.8.1
[3.8.0]: https://github.com/PalmEmanuel/AzBobbyTables/compare/v3.7.1...v3.8.0
[3.7.1]: https://github.com/PalmEmanuel/AzBobbyTables/compare/v3.7.0...v3.7.1
[3.7.0]: https://github.com/PalmEmanuel/AzBobbyTables/compare/v3.6.1...v3.7.0
[3.6.1]: https://github.com/PalmEmanuel/AzBobbyTables/compare/v3.6.0...v3.6.1
[3.6.0]: https://github.com/PalmEmanuel/AzBobbyTables/compare/v3.5.0...v3.6.0
[3.5.0]: https://github.com/PalmEmanuel/AzBobbyTables/compare/v3.4.2...v3.5.0
[3.4.2]: https://github.com/PalmEmanuel/AzBobbyTables/compare/v3.4.1...v3.4.2
[3.4.1]: https://github.com/PalmEmanuel/AzBobbyTables/compare/v3.4.0...v3.4.1
[3.4.0]: https://github.com/PalmEmanuel/AzBobbyTables/compare/v3.3.2...v3.4.0
[3.3.2]: https://github.com/PalmEmanuel/AzBobbyTables/compare/v3.3.1...v3.3.2
[3.3.1]: https://github.com/PalmEmanuel/AzBobbyTables/compare/v3.3.0...v3.3.1
[3.3.0]: https://github.com/PalmEmanuel/AzBobbyTables/compare/v3.2.1...v3.3.0
[3.2.1]: https://github.com/PalmEmanuel/AzBobbyTables/compare/v3.2.0...v3.2.1
[3.2.0]: https://github.com/PalmEmanuel/AzBobbyTables/compare/v3.1.3...v3.2.0
[3.1.3]: https://github.com/PalmEmanuel/AzBobbyTables/compare/v3.1.2...v3.1.3
[3.1.2]: https://github.com/PalmEmanuel/AzBobbyTables/compare/d854153aca6c5cce35a123deb86653a0d3289b07...v3.1.2
