Default presenter role of "Everyone" lets any participant share screen content — including hostile attendees. Restrict to organizer / co-organizer.

**Remediation Action**

```powershell
Set-CsTeamsMeetingPolicy -Identity Global -DesignatedPresenterRoleMode OrganizerOnlyUserOverride
```

**Links**
- [CIS Microsoft 365 Foundations Benchmark v7.0.0 - 8.5.6](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
