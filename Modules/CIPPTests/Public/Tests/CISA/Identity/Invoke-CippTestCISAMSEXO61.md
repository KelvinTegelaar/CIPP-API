Contact folders SHALL NOT be shared with all domains, although they MAY be shared with specific domains.

Sharing contact folders with external domains can expose sensitive organizational information. Limiting contact sharing to specific approved domains reduces the risk of information disclosure.

**Remediation Action:**

1. Navigate to Exchange Admin Center > Organization > Sharing
2. Review sharing policies
3. Remove or modify policies that allow contact sharing with all domains
4. Or use PowerShell:
```powershell
Set-SharingPolicy -Identity "Default Sharing Policy" -Domains @{Remove="*:ContactsSharing"}
```

**Links:**
- [CISA SCubaGear EXO Baseline - MS.EXO.6.1](https://github.com/cisagov/ScubaGear/blob/main/PowerShell/ScubaGear/baselines/exo.md#msexo61v1)
- [Sharing policies in Exchange Online](https://learn.microsoft.com/exchange/sharing/sharing-policies/sharing-policies)

<!--- Results --->
%TestResult%
