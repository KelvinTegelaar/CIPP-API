If 8.2.2 must be relaxed for collaboration, this control mitigates by ensuring external users can't be the *initiator* of a chat — internal users must invite first.

**Remediation Action**

```powershell
Set-CsTeamsMessagingPolicy -Identity Global -UseB2BInvitesToAddExternalUsers $false
```

**Links**
- [CIS Microsoft 365 Foundations Benchmark v7.0.0 - 8.2.3](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
