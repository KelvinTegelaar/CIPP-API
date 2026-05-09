SMTP basic auth bypasses MFA and is a frequent vector for password spray and credential stuffing. Disable tenant-wide.

**Remediation Action**

```powershell
Set-TransportConfig -SmtpClientAuthenticationDisabled $true
```

**Links**
- [CIS Microsoft 365 Foundations Benchmark v6.0.1 - 6.5.4](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
