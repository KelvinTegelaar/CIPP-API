Mailbox intelligence SHALL be enabled.

Mailbox intelligence uses machine learning to analyze user email patterns and relationships, identifying anomalous sender behavior that may indicate impersonation attempts. This AI-powered protection adapts to each user's communication patterns for more accurate threat detection.

**Remediation Action:**

1. Navigate to Microsoft 365 Defender portal > Email & collaboration > Policies & rules > Threat policies > Anti-phishing
2. Edit preset security policies or custom anti-phishing policies
3. Under Impersonation section, enable:
   - Enable mailbox intelligence
   - Enable intelligence for impersonation protection
4. Or use PowerShell:
```powershell
Set-AntiPhishPolicy -Identity "Standard Preset Security Policy" `
    -EnableMailboxIntelligence $true `
    -EnableMailboxIntelligenceProtection $true
```

**Links:**
- [CISA SCubaGear EXO Baseline - MS.EXO.11.3](https://github.com/cisagov/ScubaGear/blob/main/PowerShell/ScubaGear/baselines/exo.md#msexo113v1)
- [Mailbox intelligence in anti-phishing policies](https://learn.microsoft.com/microsoft-365/security/office-365-security/anti-phishing-policies-about#impersonation-settings-in-anti-phishing-policies-in-microsoft-defender-for-office-365)

<!--- Results --->
%TestResult%
