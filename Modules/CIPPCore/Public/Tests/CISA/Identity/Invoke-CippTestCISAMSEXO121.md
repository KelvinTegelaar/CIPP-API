Allowed sender lists SHOULD NOT be used.

Adding senders to the tenant allow list bypasses all spam, phishing, and spoofing protection. Compromised or spoofed allowed senders can be used to deliver malicious content directly to users' inboxes without any filtering.

**Remediation Action:**

1. Navigate to Microsoft 365 Defender portal > Policies & rules > Threat policies > Tenant Allow/Block Lists
2. Review and remove entries from the "Allow" list under "Senders"
3. Or use PowerShell:
```powershell
# List all allowed senders
Get-TenantAllowBlockListItems -ListType Sender -Action Allow

# Remove specific allowed sender
Remove-TenantAllowBlockListItems -ListType Sender -Ids <submission-id>
```

**Links:**
- [CISA SCubaGear EXO Baseline - MS.EXO.12.1](https://github.com/cisagov/ScubaGear/blob/main/PowerShell/ScubaGear/baselines/exo.md#msexo121v1)
- [Manage the Tenant Allow/Block List](https://learn.microsoft.com/microsoft-365/security/office-365-security/tenant-allow-block-list-about)

<!--- Results --->
%TestResult%
