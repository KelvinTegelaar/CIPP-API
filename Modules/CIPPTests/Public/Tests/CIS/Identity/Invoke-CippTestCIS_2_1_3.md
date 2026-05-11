An internal user sending malware almost always means a compromised account. Admin notifications make compromise visible immediately.

**Remediation Action**

```powershell
Set-MalwareFilterPolicy -Identity Default -EnableInternalSenderAdminNotifications $true -InternalSenderAdminAddress 'soc@contoso.com'
```

**Links**
- [CIS Microsoft 365 Foundations Benchmark v6.0.1 - 2.1.3](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
