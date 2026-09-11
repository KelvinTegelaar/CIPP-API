Emails identified as containing malware SHALL be quarantined or dropped.

Ensuring that emails containing malware are immediately quarantined or deleted prevents malicious content from reaching users' mailboxes. This is a critical security control that stops malware distribution at the email gateway level.

**Remediation Action:**

1. Navigate to Microsoft 365 Defender portal > Email & collaboration > Policies & rules > Threat policies > Anti-malware
2. Select each malware filter policy
3. Under "Protection settings" enable the common attachments filter and set its action so matching mail is either quarantined or rejected (dropped)
4. Or use PowerShell (FileTypeAction accepts `Quarantine` or `Reject`):
```powershell
Set-MalwareFilterPolicy -Identity "Default" -EnableFileFilter $true -FileTypeAction Quarantine
# Or reject (drop) matching mail instead
Set-MalwareFilterPolicy -Identity "Default" -EnableFileFilter $true -FileTypeAction Reject
```

**Links:**
- [CISA ScubaGear EXO Baseline - MS.EXO.10.2](https://github.com/cisagov/ScubaGear/blob/main/PowerShell/ScubaGear/baselines/exo.md#msexo102v1)
- [Configure anti-malware policies](https://learn.microsoft.com/microsoft-365/security/office-365-security/anti-malware-protection-configure)

<!--- Results --->
%TestResult%
