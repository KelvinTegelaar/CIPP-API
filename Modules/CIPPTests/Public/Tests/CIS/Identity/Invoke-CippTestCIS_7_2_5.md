External users should not be able to broaden the audience for content they were given access to. Disabling re-sharing keeps distribution under the control of the file owner.

**Remediation Action**

```powershell
Set-SPOTenant -PreventExternalUsersFromResharing $true
```

**Links**
- [CIS Microsoft 365 Foundations Benchmark v6.0.1 - 7.2.5](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
