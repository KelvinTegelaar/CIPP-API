Anonymous users in meeting chat can drop links and files visible to every attendee. Disabling chat for anonymous users removes that vector.

**Remediation Action**

```powershell
Set-CsTeamsMeetingPolicy -Identity Global -MeetingChatEnabledType EnabledExceptAnonymous
```

**Links**
- [CIS Microsoft 365 Foundations Benchmark v6.0.1 - 8.5.5](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
