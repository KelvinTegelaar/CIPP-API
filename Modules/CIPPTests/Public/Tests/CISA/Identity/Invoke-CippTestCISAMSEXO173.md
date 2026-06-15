Audit logs SHALL be maintained for at least the minimum duration dictated by OMB M-21-31 (1 year).

Maintaining audit logs for an adequate retention period is essential for security investigations, compliance audits, and meeting federal record-keeping requirements. A minimum of one year retention allows organizations to investigate incidents and establish historical baselines.

**Remediation Action:**

1. Navigate to Microsoft Purview compliance portal > Data lifecycle management > Microsoft 365 retention > Retention policies
2. Create or modify retention policy for audit logs
3. Or use PowerShell:
```powershell
# Enable admin audit logging (provides 1 year retention)
Set-AdminAuditLogConfig -AdminAuditLogEnabled $true

# For longer retention, configure retention policies in Purview
```

**Links:**
- [CISA SCubaGear EXO Baseline - MS.EXO.17.3](https://github.com/cisagov/ScubaGear/blob/main/PowerShell/ScubaGear/baselines/exo.md#msexo173v1)
- [Audit log retention policies](https://learn.microsoft.com/purview/audit-log-retention-policies)

<!--- Results --->
%TestResult%
