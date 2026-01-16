Microsoft Purview Audit (Standard) logging SHALL be enabled.

Audit logging captures user and administrator activities across Microsoft 365 services, providing essential forensic data for security investigations, compliance requirements, and detecting unauthorized access or data breaches.

**Remediation Action:**

1. Navigate to Microsoft Purview compliance portal > Audit
2. Turn on audit log search
3. Or use PowerShell:
```powershell
Set-AdminAuditLogConfig -UnifiedAuditLogIngestionEnabled $true
```

**Links:**
- [CISA SCubaGear EXO Baseline - MS.EXO.17.1](https://github.com/cisagov/ScubaGear/blob/main/PowerShell/ScubaGear/baselines/exo.md#msexo171v1)
- [Turn audit log search on or off](https://learn.microsoft.com/purview/audit-log-enable-disable)

<!--- Results --->
%TestResult%
