Mailbox auditing SHALL be enabled.

Mailbox auditing logs user and administrator actions in mailboxes, providing critical forensic data for security investigations and compliance requirements. This enables detection of unauthorized access and data exfiltration attempts.

**Remediation Action:**

1. Navigate to Microsoft Purview compliance portal > Audit
2. Ensure mailbox auditing is turned on
3. Or use PowerShell:
```powershell
Set-OrganizationConfig -AuditDisabled $false
```

**Links:**
- [CISA SCubaGear EXO Baseline - MS.EXO.13.1](https://github.com/cisagov/ScubaGear/blob/main/PowerShell/ScubaGear/baselines/exo.md#msexo131v1)
- [Manage mailbox auditing](https://learn.microsoft.com/purview/audit-mailboxes)

<!--- Results --->
%TestResult%
