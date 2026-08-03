# Upstream Delta — CIPP-API — 2026-08-03

Cycle type: **Light/medium delta** (upstream **10.7.3 → 10.7.5**).
Sync base: `f1b2c93d5` (upstream/master at 07-28 cycle) → `upstream/master` @ `245d9d35b`.
Branch: `manage365/upstream-sync-cipp-api-20260803`
Backup tag: `backup/pre-upstream-sync-cipp-api-20260803`

3 merge commits (CyberDrain #103, #115, #132). Large surface: AzBobbyTables upgrade,
Intune template drift fixes, audit-log V2, groups/device membership, SSO/custom-domain
additions (skipped).

## Commits

| SHA | Date | Subject |
|-----|------|---------|
| `019f62b7a` | 2026-07-29 | Merge PR #103 from CyberDrain/dev |
| `82ab2621f` | 2026-07-29 | Merge PR #115 from CyberDrain/dev |
| `245d9d35b` | 2026-07-30 | Merge PR #132 from CyberDrain/dev → **10.7.5** |

## Triage — Apply

| Theme | Paths | Notes |
|---|---|---|
| AzBobbyTables 3.6.2 | `Modules/AzBobbyTables/3.6.2/**` | Drop 3.6.0 if present; fork has 3.4.0/3.5.1 |
| Table wrappers | `Add-CIPPAzDataTableEntity.ps1`, `Get-CIPPAzDatatableEntity.ps1`, new `Remove-CIPPAzDataTableEntity.ps1` | Thin wrappers over large-entity cmdlets |
| Call-site renames | Many `Remove-AzDataTableEntity` → `Remove-CIPPAzDataTableEntity` | Mechanical after wrappers land |
| ConversionTable | `Config/ConversionTable.csv` | Data-only |
| Intune template drift | `Get-CIPPIntunePolicyName`, `Merge-CIPPIntuneTemplateIdentity`, `Select-CIPPIntuneAvailableSetting`, `Invoke-CIPPStandardIntuneTemplate`, `Set-CIPPIntunePolicy`, `Compare-CIPPIntuneObject`, `Repair-CIPPIntuneTemplateNesting`, `Invoke-ExecCompareIntunePolicy` + tests | High value |
| Groups | `New-CIPPGroup.ps1` (`disableNesting`), `Invoke-EditGroup.ps1` (`AddDevice`) | Pair with FE |
| Audit log V2 | `Test-CIPPAuditLogRules`, `Push-AuditLogDownloadV2`, `Push-AuditLogTenantProcessV2`, related + webhook tests | Apply with Pester |
| SafeLinks | `Invoke-CIPPStandardSafeLinksPolicy.ps1` | Low risk |
| Partner webhook | `Invoke-ExecPartnerWebhook.ps1` + new `Get-CIPPHostname.ps1` | Adapt — SWA-safe without SSO |
| SAM | `Config/SAMManifest.json` Scope `3bc15058-…` | Union-merge; CPV after deploy |

## Triage — Skip / Defer

| Theme | Outcome | Why |
|---|---|---|
| `Update-CIPPSSOPreconsent.ps1`, `Initialize-CIPPAuth` SSO hook, `Invoke-ExecSSOSetup`, SSO tests | **Skip** | SSO family — SWA lockout / Craft |
| `Invoke-ExecAppServiceDomains.ps1` | **Defer** | No App Service custom-domain UI in fork |
| `Start-SchedulerOrchestrator` `$ValidTypes` destructive cleanup | **Still defer** | Carryover from 07-28 |
| `version_latest.txt` | **Chore** | Bump with Manage365 release at end |

## Deferred feature backlog (unchanged stance)

SSO/CIPP Users Skip · MCP Planned (design first) · Worker health Deferred · Teams V2 Defer ·
Custom domains Defer · Container Skip · Purview DLP next feature intake · Custom Test Alerting
after CLM settle.
