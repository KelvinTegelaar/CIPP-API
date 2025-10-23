# Changelog for the module

The format is based on and uses the types of changes according to [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

-   Added `-OperationType` parameter to `Add-AzDataTableEntity` and `Update-AzDataTableEntity` to support merge or replace operations [#81](https://github.com/PalmEmanuel/AzBobbyTables/pull/81)

## [3.3.0] - 2024-10-18

### Added

-   Added command `Get-AzDataTable` to get the names of tables in a storage account [#77](https://github.com/PalmEmanuel/AzBobbyTables/issues/77)

### Changed

-   Implemented TableServiceClient to support operations on tables in the storage account.

## [3.2.1] - 2024-07-09

### Fixed

-   Fixed bug where empty lines were written to console.

## [3.2.0] - 2024-03-21

### Added

-   ETag validation for Update- & Remove-AzDataTableEntity ([#58](https://github.com/PalmEmanuel/AzBobbyTables/issues/58))

### Fixed

-   Missing examples of Remove-AzDataTableEntity ([#62](https://github.com/PalmEmanuel/AzBobbyTables/issues/62))

## [3.1.3] - 2024-01-20

### Added

-   Added Sampler ([#48](https://github.com/PalmEmanuel/AzBobbyTables/issues/48)).
-   Added support for user-assigned managed identities ([#54](https://github.com/PalmEmanuel/AzBobbyTables/issues/54)).

## [3.1.2] - 2024-01-05

### Added

-   Help documentation for a DateTime problem caused by the SDK (#43).

## 3.1.1 - 2023-05-03

[Unreleased]: https://github.com/PalmEmanuel/AzBobbyTables/compare/v3.3.2...HEAD

[3.3.2]: https://github.com/PalmEmanuel/AzBobbyTables/compare/v3.3.1...v3.3.2

[3.3.1]: https://github.com/PalmEmanuel/AzBobbyTables/compare/v3.3.0...v3.3.1

[3.3.0]: https://github.com/PalmEmanuel/AzBobbyTables/compare/v3.2.1...v3.3.0

[3.2.1]: https://github.com/PalmEmanuel/AzBobbyTables/compare/v3.2.0...v3.2.1

[3.2.0]: https://github.com/PalmEmanuel/AzBobbyTables/compare/v3.1.3...v3.2.0

[3.1.3]: https://github.com/PalmEmanuel/AzBobbyTables/compare/v3.1.2...v3.1.3

[3.1.2]: https://github.com/PalmEmanuel/AzBobbyTables/compare/d854153aca6c5cce35a123deb86653a0d3289b07...v3.1.2
