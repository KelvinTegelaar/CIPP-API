Defaulting to View prevents accidental Edit-grants when sharing files. Edit must be a deliberate user choice.

**Remediation Action**

```powershell
Set-SPOTenant -DefaultLinkPermission View
```

**Links**
- [CIS Microsoft 365 Foundations Benchmark v6.0.1 - 7.2.11](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
