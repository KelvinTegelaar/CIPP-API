"Give control" hands keyboard / mouse to another participant, who can then run commands on the presenter's machine. External participants must not have this ability.

**Remediation Action**

```powershell
Set-CsTeamsMeetingPolicy -Identity Global -AllowExternalParticipantGiveRequestControl $false
```

**Links**
- [CIS Microsoft 365 Foundations Benchmark v6.0.1 - 8.5.7](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
