External sender warnings SHALL be implemented.

External sender warnings help users identify emails from outside the organization, reducing the risk of phishing and social engineering attacks. This visual indicator alerts users to exercise caution when interacting with external emails.

**Remediation Action:**

1. Navigate to Microsoft 365 Defender portal > Email & collaboration > Policies & rules > Threat policies
2. Under "Rules", select "External sender"
3. Enable external sender warnings
4. Or use PowerShell:
```powershell
Set-ExternalInOutlook -Enabled $true
```

**Links:**
- [CISA SCubaGear EXO Baseline - MS.EXO.7.1](https://github.com/cisagov/ScubaGear/blob/main/PowerShell/ScubaGear/baselines/exo.md#msexo71v1)
- [External sender warnings](https://learn.microsoft.com/microsoft-365/security/office-365-security/external-email-forwarding)

<!--- Results --->
%TestResult%
