External calendar sharing exposes meeting subjects, attendees and locations to people outside the organisation. CIS recommends disabling the default sharing policy.

**Remediation Action**

```powershell
Get-SharingPolicy | Set-SharingPolicy -Enabled $false
```

**Links**
- [CIS Microsoft 365 Foundations Benchmark v6.0.1 - 1.3.3](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
