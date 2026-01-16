High confidence spam SHALL be quarantined.

High confidence spam represents emails that Microsoft's filtering systems are very confident are spam. Quarantining these messages rather than delivering them to junk mail folders provides better protection and allows administrators to review and release legitimate emails if needed.

**Remediation Action:**

1. Navigate to Microsoft 365 Defender portal > Email & collaboration > Policies & rules > Threat policies > Anti-spam
2. Select each anti-spam policy
3. Under "Actions":
   - Set "High confidence spam" action to "Quarantine message"
4. Or use PowerShell:
```powershell
Set-HostedContentFilterPolicy -Identity "Default" -HighConfidenceSpamAction Quarantine
```

**Links:**
- [CISA SCubaGear EXO Baseline - MS.EXO.14.1](https://github.com/cisagov/ScubaGear/blob/main/PowerShell/ScubaGear/baselines/exo.md#msexo141v2)
- [Configure anti-spam policies](https://learn.microsoft.com/microsoft-365/security/office-365-security/anti-spam-policies-configure)

<!--- Results --->
%TestResult%
