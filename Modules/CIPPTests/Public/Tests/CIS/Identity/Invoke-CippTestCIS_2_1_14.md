An allowed sender domain bypasses spam, malware and phishing checks for that domain. Attackers regularly spoof allowlisted domains.

**Remediation Action**

```powershell
Set-HostedContentFilterPolicy -Identity Default -AllowedSenderDomains @()
```

**Links**
- [CIS Microsoft 365 Foundations Benchmark v7.0.0 - 2.1.14](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
