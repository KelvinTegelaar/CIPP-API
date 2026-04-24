Impersonation protection checks SHOULD be used.

Impersonation protection defends against phishing attacks where attackers impersonate trusted users or domains. These checks analyze sender patterns, domain similarities, and user behavior to identify and block sophisticated impersonation attempts before they reach users.

**Remediation Action:**

1. Navigate to Microsoft 365 Defender portal > Email & collaboration > Policies & rules > Threat policies > Preset security policies
2. Enable either Standard or Strict preset security policy
3. Ensure policies include appropriate user and domain protection
4. Or use PowerShell:
```powershell
# Enable standard preset security policy
Enable-EOPProtectionPolicyRule -Identity "Standard Preset Security Policy"
Enable-ATPProtectionPolicyRule -Identity "Standard Preset Security Policy"
```

**Links:**
- [CISA SCubaGear EXO Baseline - MS.EXO.11.1](https://github.com/cisagov/ScubaGear/blob/main/PowerShell/ScubaGear/baselines/exo.md#msexo111v1)
- [Preset security policies](https://learn.microsoft.com/microsoft-365/security/office-365-security/preset-security-policies)

<!--- Results --->
%TestResult%
