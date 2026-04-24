URL comparison with a block-list SHOULD be enabled.

Safe Links provides time-of-click verification of URLs in email messages and Office documents. This protection helps prevent users from clicking on malicious links by checking URLs against a dynamically updated block-list of known malicious websites.

**Remediation Action:**

1. Navigate to Microsoft 365 Defender portal > Email & collaboration > Policies & rules > Threat policies > Safe Links
2. Select each Safe Links policy
3. Under "URL & click protection settings":
   - Enable "On: Safe Links checks a list of known, malicious links when users click links in email"
4. Or use PowerShell:
```powershell
Set-SafeLinksPolicy -Identity "Default" -EnableSafeLinksForEmail $true
```

**Links:**
- [CISA SCubaGear EXO Baseline - MS.EXO.15.1](https://github.com/cisagov/ScubaGear/blob/main/PowerShell/ScubaGear/baselines/exo.md#msexo151v1)
- [Set up Safe Links policies](https://learn.microsoft.com/microsoft-365/security/office-365-security/safe-links-policies-configure)

<!--- Results --->
%TestResult%
