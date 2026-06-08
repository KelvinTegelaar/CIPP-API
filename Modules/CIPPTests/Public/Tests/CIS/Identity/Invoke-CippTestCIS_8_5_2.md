If anonymous users can start a meeting, they can also start an unattended meeting and host content sharing without any organisational presence.

**Remediation Action**

```powershell
Set-CsTeamsMeetingPolicy -Identity Global -AllowAnonymousUsersToStartMeeting $false
```

**Links**
- [CIS Microsoft 365 Foundations Benchmark v7.0.0 - 8.5.2](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
