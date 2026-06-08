External meeting chats persist across calls and create a long-lived chat thread with non-federated externals. Disable to limit chat to the meeting itself.

**Remediation Action**

```powershell
Set-CsTeamsMeetingPolicy -Identity Global -AllowExternalNonTrustedMeetingChat $false
```

**Links**
- [CIS Microsoft 365 Foundations Benchmark v7.0.0 - 8.5.8](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
