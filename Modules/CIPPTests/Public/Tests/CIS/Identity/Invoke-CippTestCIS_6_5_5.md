Direct Send lets unauthenticated SMTP clients send email *as your domain* to your tenant mailboxes. It is a frequent vector for internal phishing because the spoof passes implicit trust checks.

**Remediation Action**

Audit which devices currently rely on Direct Send (printers, line-of-business apps), migrate them to authenticated SMTP relay, then:

```powershell
Set-OrganizationConfig -RejectDirectSend $true
```

**Links**
- [CIS Microsoft 365 Foundations Benchmark v6.0.1 - 6.5.5](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
