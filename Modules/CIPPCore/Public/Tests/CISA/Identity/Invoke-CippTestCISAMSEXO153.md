User click tracking SHOULD be disabled.

Click tracking in Safe Links can collect information about which URLs users click, which may raise privacy concerns. CISA recommends disabling this feature to protect user privacy while still maintaining URL protection capabilities.

**Remediation Action:**

1. Navigate to Microsoft 365 Defender portal > Email & collaboration > Policies & rules > Threat policies > Safe Links
2. Select each Safe Links policy
3. Under "URL & click protection settings":
   - Disable "Track user clicks"
4. Or use PowerShell:
```powershell
Set-SafeLinksPolicy -Identity "Default" -TrackUserClicks $false
```

**Links:**
- [CISA SCubaGear EXO Baseline - MS.EXO.15.3](https://github.com/cisagov/ScubaGear/blob/main/PowerShell/ScubaGear/baselines/exo.md#msexo153v1)
- [Set up Safe Links policies](https://learn.microsoft.com/microsoft-365/security/office-365-security/safe-links-policies-configure)

<!--- Results --->
%TestResult%
