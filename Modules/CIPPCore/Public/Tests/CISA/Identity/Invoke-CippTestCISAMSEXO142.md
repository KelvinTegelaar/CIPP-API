Spam and high confidence spam SHALL be moved to either the junk email folder or the quarantine folder.

Properly handling spam emails prevents users from being exposed to potentially malicious content while still allowing recovery of false positives. Moving spam to junk folders or quarantine provides a balance between security and usability.

**Remediation Action:**

1. Navigate to Microsoft 365 Defender portal > Email & collaboration > Policies & rules > Threat policies > Anti-spam
2. Select each anti-spam policy
3. Under "Actions":
   - Set "Spam" action to "Move message to Junk Email folder" or "Quarantine message"
4. Or use PowerShell:
```powershell
Set-HostedContentFilterPolicy -Identity "Default" -SpamAction MoveToJmf
# Or
Set-HostedContentFilterPolicy -Identity "Default" -SpamAction Quarantine
```

**Links:**
- [CISA SCubaGear EXO Baseline - MS.EXO.14.2](https://github.com/cisagov/ScubaGear/blob/main/PowerShell/ScubaGear/baselines/exo.md#msexo142v1)
- [Configure anti-spam policies](https://learn.microsoft.com/microsoft-365/security/office-365-security/anti-spam-policies-configure)

<!--- Results --->
%TestResult%
