Calendar details SHALL NOT be shared with all domains, although they MAY be shared with specific domains.

Sharing detailed calendar information (including meeting subjects, locations, and attendees) with all external domains can expose sensitive business information. Limiting detailed calendar sharing to specific approved domains protects organizational privacy.

**Remediation Action:**

1. Navigate to Exchange Admin Center > Organization > Sharing
2. Review sharing policies
3. Ensure wildcard (*) domains only allow free/busy time, not detailed information
4. Or use PowerShell:
```powershell
# Allow only free/busy with all domains
Set-SharingPolicy -Identity "Default Sharing Policy" -Domains "*:CalendarSharingFreeBusySimple"

# For specific domains, you can allow details
Set-SharingPolicy -Identity "Default Sharing Policy" -Domains @{Add="partner.com:CalendarSharingFreeBusyDetail"}
```

**Links:**
- [CISA SCubaGear EXO Baseline - MS.EXO.6.2](https://github.com/cisagov/ScubaGear/blob/main/PowerShell/ScubaGear/baselines/exo.md#msexo62v1)
- [Sharing policies in Exchange Online](https://learn.microsoft.com/exchange/sharing/sharing-policies/sharing-policies)

<!--- Results --->
%TestResult%
