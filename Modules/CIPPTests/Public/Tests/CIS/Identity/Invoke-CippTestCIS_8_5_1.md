Anonymous meeting joiners are unauthenticated — there is no audit trail of *who* attended. Disable anonymous join unless you run external-facing webinars.

**Remediation Action**

```powershell
Set-CsTeamsMeetingPolicy -Identity Global -AllowAnonymousUsersToJoinMeeting $false
```

**Links**
- [CIS Microsoft 365 Foundations Benchmark v6.0.1 - 8.5.1](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
