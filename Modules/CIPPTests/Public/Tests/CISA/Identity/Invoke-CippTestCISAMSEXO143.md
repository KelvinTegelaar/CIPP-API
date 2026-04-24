Allowed senders and domains SHOULD NOT be added to the anti-spam filter.

Adding senders or domains to the allowed list bypasses spam filtering, which can be exploited by attackers. Compromised accounts or spoofed emails from allowed domains will bypass security controls and reach users' inboxes unchecked.

**Remediation Action:**

1. Navigate to Microsoft 365 Defender portal > Email & collaboration > Policies & rules > Threat policies > Anti-spam
2. Select each anti-spam policy
3. Under "Allowed and blocked senders and domains":
   - Review and remove entries from "Allowed senders" list
   - Review and remove entries from "Allowed domains" list
4. Or use PowerShell:
```powershell
Set-HostedContentFilterPolicy -Identity "Default" -AllowedSenders @() -AllowedSenderDomains @()
```

**Links:**
- [CISA SCubaGear EXO Baseline - MS.EXO.14.3](https://github.com/cisagov/ScubaGear/blob/main/PowerShell/ScubaGear/baselines/exo.md#msexo143v1)
- [Configure allowed and blocked senders](https://learn.microsoft.com/microsoft-365/security/office-365-security/create-safe-sender-lists-in-office-365)

<!--- Results --->
%TestResult%
