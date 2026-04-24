Real-time suspicious URL and file-link scanning SHOULD be enabled.

Real-time scanning checks suspicious URLs at the time of click, even if the URL wasn't initially identified as malicious. This provides additional protection against rapidly evolving threats and newly created malicious websites.

**Remediation Action:**

1. Navigate to Microsoft 365 Defender portal > Email & collaboration > Policies & rules > Threat policies > Safe Links
2. Select each Safe Links policy
3. Under "URL & click protection settings":
   - Enable "Apply Safe Links to email messages sent within the organization"
   - Enable "Apply real-time URL scanning for suspicious links and links that point to files"
4. Or use PowerShell:
```powershell
Set-SafeLinksPolicy -Identity "Default" -ScanUrls $true
```

**Links:**
- [CISA SCubaGear EXO Baseline - MS.EXO.15.2](https://github.com/cisagov/ScubaGear/blob/main/PowerShell/ScubaGear/baselines/exo.md#msexo152v1)
- [Set up Safe Links policies](https://learn.microsoft.com/microsoft-365/security/office-365-security/safe-links-policies-configure)

<!--- Results --->
%TestResult%
