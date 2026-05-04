The connection filter safe list bypasses content filtering for senders Microsoft considers reputable. CIS recommends turning it off so all mail is filtered consistently.

**Remediation Action**

```powershell
Set-HostedConnectionFilterPolicy -Identity Default -EnableSafeList $false
```

**Links**
- [CIS Microsoft 365 Foundations Benchmark v6.0.1 - 2.1.13](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
