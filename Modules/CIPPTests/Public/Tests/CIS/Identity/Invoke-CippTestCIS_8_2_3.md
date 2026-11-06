If 8.2.2 must be relaxed for collaboration, this control mitigates by ensuring external users can't be the *initiator* of a chat — internal users must invite first.

**Remediation Action**

Teams admin centre > Users > External access > Unmanaged Teams accounts: uncheck "People in my org can join external meetings and receive new chats from users who have unmanaged Microsoft accounts". Turning off communication with unmanaged Teams accounts entirely also satisfies this control.

```powershell
Set-CsExternalAccessPolicy -Identity Global -EnableTeamsConsumerInbound $false
```

**Links**
- [CIS Microsoft 365 Foundations Benchmark v7.0.0 - 8.2.3](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
