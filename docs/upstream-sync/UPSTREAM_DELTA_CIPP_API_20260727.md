# Upstream Delta — CIPP-API — 2026-07-27

Cycle type: **Major delta** (upstream 10.6.1 → **10.7.2**).
Sync base: tag `10.6.1` (last cycle July 13) → `upstream/master` @ `d63b7fae3`.
86 commits in range (72 non-merge + release squashes).

## Structural change upstream

Upstream development moved to the **CyberDrain org**. Releases 10.7.0
(`edd3481be`), 10.7.1 (`9d43278ec`) and 10.7.2 (`d63b7fae3`) each landed on
master as **single-parent squash commits** on top of the individually merged
dev commits. Triage therefore splits into:

1. **True commits** (2026-07-13 → 07-21) — cherry-pickable individually.
2. **Squash-only content** (10.7.x) — ported as path-scoped diffs vs
   `upstream/master` per feature area.

Headline squash content: SAM/auth access-scope rework, **removal of the
vendored `Modules/MicrosoftTeams` module** (139 files, ~477k lines) replaced by
a direct `New-TeamsRequestV2` API layer, SharePoint permissions
report/editor family, SharePoint templated deployments hardening, Intune app
template deploy standard, CIPPSharp REST client.

## Triage — Apply (cherry-pick, low/medium risk)

| Upstream | Subject | Notes |
|---|---|---|
| `b2985a6f0` | assignments default append | Fork adapted Set-CIPPAssignedPolicy/Application (direction-scoped) — watch conflicts |
| `ad9caf3ff` | OneDrive root permissions cache boilerplate | New files; previously deferred, now cheap |
| `610ec61e7` | Get-GraphToken AppCache drift | Fork took upstream Get-GraphToken at SAM-cert intake |
| `176d43baa` | partner webhook external URI | |
| `5b42363cd` | nudge-mfa group targeting + auth method selection | New Set-CIPPRegistrationCampaign + ExecRegistrationCampaign; FE pair `ffbca69a5` |
| `2da187218` | snooze to new permission | Fork has snooze endpoints |
| `8f1dd767a` | smart lockout normalize | standards.json part = curated adapt |
| `25f38c58f` | CISA EXO 1.4.1 output | |
| `285685273` | ORCA121 ZAP actions | |
| `2bc0c8e26` | retention days integer cast | |
| `45bd6c996` | test data field projection + CIPPSharp | Fork CIPPSharp aligned upstream |
| `98f0778d8` | CIS/ZTNA test field refs | |
| `003e39f6b` | drift Intune name pairings + tests | |
| `01242ff57` | Set-CIPPUser group routing | Fork has Set-CIPPUser |
| `9368bca07` | SharePoint tests | With SP-templates family |
| `eddef9284` | Set-CIPPSAMAdminRoles cleanup | |
| `ffab43e1a`+`077c0689d` | Site (in)activity cache + report + single lookup | CIPPDBCacheTypes.json adapt; FE pair `bfc83afd7` |
| `996e75c98` | CPV retry guard removal | |
| `ed577f689` | quota alert mailbox types | FE pair `3ac0596f0` |
| `9b5bdd844` | schema extension status | |
| `fd245427d` | app-approval linked permission set | FE pair `3bea4e3b2` |
| `cb1876962` | TeamsDisableResourceAccounts standard | FE pair `0b879d130` |
| `ffd1d69ec` | CA template licenseAvailable P2 | |
| `1072570b5` | DisableM365GroupUsers AllowedToCreateGroups | FE pair `1f4dc9175` |
| `532fff7c6` | MAM deviceAppManagement endpoints | Set-CIPPAssignedPolicy fork-adapted — adapt |
| `1cfa4bfbf` | stale alert cutoff | |
| `0c13c98d0` | writeback reset synced user | |
| `7403b2f60` | community repo #6319 | |
| `6413f0325`+`2ddca8eaa` | JSON validation CI | FE pair `c259fe4ea` |
| `d348de650` | CSP license / Sherweb #6390 | FE pair `b4373e540` |
| `99787a04a` | drift: exclude SP admin center deviations | |
| `4ee94dcba` | GDAP age group in tenant groups | FE pair `341b4555e` |
| `206f9b155` | shadow AI tools alert | FE pair `01180c005` |
| `e704077c8` | audit log token denial = disable | Fork has V2 pipeline |
| `06025c8c6` | QuarantineRequestAlert write-alert typo | Standards file, not quarantine portal |
| `9e518828c` | CA GuestsOrExternalUsers spelling | |
| `ac5a198d8` | standards remediation error logging (13 auth-method standards) | |
| `b4133f874` | Intune false App Protection drift | |
| `784cff5af` | preserve @odata.type on synced App Protection | |
| `951f831f5` | Sherweb migration stop after disable | |
| `15efd3dbb` | inactive licensed users alert enrichment | |
| `7d16571f7` | PWdisplayAppInformation self-check | |
| `a27aff5f4` | CA guests selector constant | |
| `f4dd2a772` | Teams switches default $false | Uses existing New-TeamsRequest (v1) — fine |
| `e0060db51` | compare policy null results | FE pair `c4bf26c4d` |
| `32c387893`+`9609ac929`+`e569d2fc2` | SharePoint templated deployments v1 + steps + skip-exists | New AsyncDeployment framework; FE pair `fcf936ddd`+`84584329f` |
| `d14159589` | autopilot profile name validation | FE pair `da107ebf2` |
| `986de0254` | standards.json align | Adapt into curated fork standards.json |
| `ba8232e2f` | PIM role cache app token | SAMManifest merge (protected) + CPV note |
| `e247438fc` | copilot policy permissions | SAMManifest merge (protected) + CPV note; fork took Copilot intake 07-15 |
| `8cde47ba5` | skip SharingLinks in DB cache run | Push-CIPPDBCacheData fork-custom — adapt |
| `5a08c2c5f` | IDictionary request inputs | Take ListMailboxes half; skip MCP half (no MCP module) |

## Triage — squash-only content to port by path diff

| Area | Outcome | Notes |
|---|---|---|
| SharePoint permissions family (`Push-DBCacheSharePointPermissionsBatch`, `Push-StoreSharePointPermissions`, `Set-CIPPDBCacheSharePointPermissions`, `Resolve-CIPPSharePointPermissionScope`, `Set-CIPPSharePointObjectPermission`, `Get-CIPPSharePointErrorMessage`, `New-CIPPSharepointSite`, `New-CIPPSharePointLibrary`, `Invoke-ListSharePointPermissions`, `Invoke-ListSitePermissions`, `Invoke-ListSiteRoleDefinitions`, `Invoke-ListSiteUserAccess`, `Invoke-ExecRemoveLibraryPermission`, `Invoke-ExecSetLibraryInheritance`, `Invoke-ExecSetLibraryPermission`) | **Apply** | Mostly new files; SAM cert prereq already in fork; FE pair = permissions-report page + PDF components |
| SP templated deployments squash hardening (`Invoke-CIPPSharePointTemplateDeploy`, `Invoke-ExecSharePointTemplate`, `Push-ExecSharePointTemplateDeploy`, `Invoke-ListSharePointTemplates`) | **Apply** | Take at upstream tip state |
| `Invoke-CIPPStandardDisableInactiveUsers` (new standard) | **Apply** | + curated standards.json entry |
| Intune app template deploy (`New-CIPPIntuneAppDeployment`, `Get-CIPPOfficeAppBody`, `Invoke-CIPPStandardIntuneAppTemplateDeploy`, `Invoke-AddOfficeApp`, `Invoke-AddStoreApp`) | **Apply** | New standard family |
| `Invoke-CIPPStandardIntuneTemplate` squash changes | **Apply** | Diff-port |
| Teams V2 (`New-TeamsRequestV2`, Teams Voice endpoints, Cs* DBCache setters, **MicrosoftTeams module deletion**) | **Defer — feature intake** | Fork has ~20 standards + DBCache on vendored module; needs dedicated migration + smoke tests |
| SAM/auth access-scope rework (`Get-CippRequestContext`, `Initialize-CippRequestContext`, access-scope cache family, `Test-CIPPAccess`, `Set-CIPPAccessRole`, `New-CippCoreRequest`, GraphHelper touch-ups) | **Defer — feature intake** | Auth-critical protected area; pairs with SSO/CIPP-user family already in backlog |
| `Invoke-ExecAppServiceDomains` + custom-domains UI | **Defer** | Self-host oriented; super-admin pages family already deferred |
| CIPPSharp `CIPPRestClient.cs` + binary | **Defer** | Bundled with auth rework |

## Triage — Skip / Already implemented / Deferred (unchanged families)

| Upstream | Outcome | Reason |
|---|---|---|
| `24db2c55c`+`9c9208669` | Skip | NinjaOne CVE group added then reverted — net zero |
| `32ab1c860`, `bc7ace6da`, `98d824463` (version part) | Skip | version_latest.txt bumps (fork versioning protected) |
| `98d824463` host.json change | Review | Check diff during batch E |
| `8c4cf8d94` | Skip | MCP module not in fork (deferred family) |
| `096abcf5b`, `bcc920892` (FE) | Defer | SSO family — planned intake |
| `835972e1a`, `6bd008143`, `cf9fc1d2f` | Skip | Container management — fork has no container endpoints (Azure Functions hosting) |
| `f697a54c6` | Defer | DLP advanced-rule files not in fork (Purview DLP family deferred) |
| `b183e48b3` | Skip | Get-CIPPCVEReport not in fork (CVE management family deferred) |
| 10.7.2 squash | Skip | version_latest.txt only |
