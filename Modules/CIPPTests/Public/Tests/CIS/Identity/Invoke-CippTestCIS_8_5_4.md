PSTN dial-in callers are anonymous from a Teams perspective — caller-ID alone is not authentication. Force them through the lobby.

**Remediation Action**

```powershell
Set-CsTeamsMeetingPolicy -Identity Global -AllowPSTNUsersToBypassLobby $false
```

**Links**
- [CIS Microsoft 365 Foundations Benchmark v6.0.1 - 8.5.4](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
