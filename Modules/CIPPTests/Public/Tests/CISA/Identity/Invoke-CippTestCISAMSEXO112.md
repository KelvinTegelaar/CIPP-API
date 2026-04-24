User warnings, comparable to the user safety tips included with EOP, SHOULD be displayed.

Safety tips provide visual warnings to users when emails contain indicators of impersonation attempts, such as similar display names, lookalike domains, or unusual character patterns. These warnings help users recognize and avoid phishing attacks.

**Remediation Action:**

1. Navigate to Microsoft 365 Defender portal > Email & collaboration > Policies & rules > Threat policies > Anti-phishing
2. Edit preset security policies or custom anti-phishing policies
3. Under Impersonation section, enable:
   - Show user impersonation safety tip
   - Show domain impersonation safety tip
   - Show unusual characters impersonation safety tip
4. Or use PowerShell:
```powershell
Set-AntiPhishPolicy -Identity "Standard Preset Security Policy" `
    -EnableSimilarUsersSafetyTips $true `
    -EnableSimilarDomainsSafetyTips $true `
    -EnableUnusualCharactersSafetyTips $true
```

**Links:**
- [CISA SCubaGear EXO Baseline - MS.EXO.11.2](https://github.com/cisagov/ScubaGear/blob/main/PowerShell/ScubaGear/baselines/exo.md#msexo112v1)
- [Safety tips in email messages](https://learn.microsoft.com/microsoft-365/security/office-365-security/anti-phishing-protection-about#safety-tips-in-email-messages)

<!--- Results --->
%TestResult%
