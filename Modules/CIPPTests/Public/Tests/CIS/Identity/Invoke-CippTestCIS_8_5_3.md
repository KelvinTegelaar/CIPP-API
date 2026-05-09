The lobby acts as a gate for unknown participants. Letting only internal users bypass it forces guests to be admitted explicitly.

**Remediation Action**

```powershell
Set-CsTeamsMeetingPolicy -Identity Global -AutoAdmittedUsers EveryoneInCompanyExcludingGuests
```

**Links**
- [CIS Microsoft 365 Foundations Benchmark v6.0.1 - 8.5.3](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
