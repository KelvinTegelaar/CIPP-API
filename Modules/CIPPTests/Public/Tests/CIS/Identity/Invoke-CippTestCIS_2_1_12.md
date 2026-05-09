IPs on the connection filter allow list bypass spam, spoof and authentication checks. CIS recommends keeping this list empty.

**Remediation Action**

```powershell
Set-HostedConnectionFilterPolicy -Identity Default -IPAllowList @()
```

**Links**
- [CIS Microsoft 365 Foundations Benchmark v6.0.1 - 2.1.12](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
