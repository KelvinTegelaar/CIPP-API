Safe lists SHOULD NOT be enabled.

Safe lists in Outlook bypass Exchange Online Protection (EOP) spam filtering, which can allow malicious emails from compromised accounts or domains on users' safe senders lists to reach their inboxes. This creates a security risk that attackers can exploit through social engineering.

**Remediation Action:**

1. Navigate to Microsoft 365 Defender portal > Email & collaboration > Policies & rules > Threat policies > Anti-spam
2. Select each anti-spam policy
3. Under "Actions":
   - Disable "Enable end-user spam notifications"
   - Or ensure "On" for safe lists is disabled
4. Or use PowerShell:
```powershell
Set-HostedContentFilterPolicy -Identity "Default" -EnableSafeList $false
```

**Links:**
- [CISA SCubaGear EXO Baseline - MS.EXO.12.2](https://github.com/cisagov/ScubaGear/blob/main/PowerShell/ScubaGear/baselines/exo.md#msexo122v1)
- [Configure anti-spam policies](https://learn.microsoft.com/microsoft-365/security/office-365-security/anti-spam-policies-configure)

<!--- Results --->
%TestResult%
