Channel email addresses bypass Exchange transport rules and Defender protections, providing a path for malicious content to reach Teams channels directly.

**Remediation Action**

```powershell
Set-CsTeamsClientConfiguration -Identity Global -AllowEmailIntoChannel $false
```

**Links**
- [CIS Microsoft 365 Foundations Benchmark v6.0.1 - 8.1.2](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
