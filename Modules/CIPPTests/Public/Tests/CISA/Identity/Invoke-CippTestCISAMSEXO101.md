Emails SHALL be filtered by attachment file types.

Email attachment filtering helps prevent malicious files from reaching users' inboxes. By blocking or quarantining emails with potentially dangerous file types, organizations can significantly reduce the risk of malware infections and data breaches.

**Remediation Action:**

1. Navigate to Microsoft 365 Defender portal > Email & collaboration > Policies & rules > Threat policies > Anti-malware
2. Select each malware filter policy
3. Under "Protection settings":
   - Enable "Enable the common attachments filter"
4. Or use PowerShell:
```powershell
Set-MalwareFilterPolicy -Identity "Default" -EnableFileFilter $true
```

**Links:**
- [CISA SCubaGear EXO Baseline - MS.EXO.10.1](https://github.com/cisagov/ScubaGear/blob/main/PowerShell/ScubaGear/baselines/exo.md#msexo101v1)
- [Configure anti-malware policies](https://learn.microsoft.com/microsoft-365/security/office-365-security/anti-malware-protection-configure)

<!--- Results --->
%TestResult%
