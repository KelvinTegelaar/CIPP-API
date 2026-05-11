DKIM cryptographically signs outbound mail so receivers can verify the message hasn't been tampered with and originated from your domain.

**Remediation Action**

```powershell
Set-DkimSigningConfig -Identity <domain> -Enabled $true
```

Publish the two CNAME records Microsoft provides before enabling.

**Links**
- [CIS Microsoft 365 Foundations Benchmark v6.0.1 - 2.1.9](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
