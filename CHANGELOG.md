# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).


## [2.2.0] - 2026-02-13
### Added
- Import scripts for entitlements and authentication methods.
- Refactored grant and revoke scripts for authentication methods to use a flat array structure and improved logging.
- Improved audit logging and fallback display names in all permission scripts.
- Updated README with all used API endpoints and best practices for required "None" mappings.
- Confirmed and documented use of `$outputContext.Data` for required attributes with "None" mapping.

### Changed
- Adjusted scripts for import functionality and proper support for the PhoneBusiness attribute.
- Refactored and standardized code formatting across all scripts for consistency.
- Improved phone number comparison logic to ignore spaces and ensure robust matching.
- Enhanced error handling and logging for better troubleshooting.

### Fixed
- Hotfix to support no mapped fields on delete actions.
- Fixed issues with phone number detection and comparison in authentication scripts.
- Fixed audit logging to always include PermissionDisplayName where possible.
- Fixed bug: BusinessPhones should be an array, not a string, in the compare attribute logic ([#6](https://github.com/Tools4everBV/HelloID-Conn-Prov-Target-KPN-Lisa/issues/6)).
- Fixed minor bugs and improved code hygiene (removed trailing whitespace, unnecessary blank lines, etc.).

## [2.1.0] - 2025-02-03
### Changed
- Refactored code formatting and various fixes ([#4](https://github.com/Tools4everBV/HelloID-Conn-Prov-Target-KPN-Lisa/pull/4))

### Contributors
- @rschouten97 made their first contribution in [#4](https://github.com/Tools4everBV/HelloID-Conn-Prov-Target-KPN-Lisa/pull/4)

## [2.0.0]
### Added
- Major improvements and new features (details not specified).


