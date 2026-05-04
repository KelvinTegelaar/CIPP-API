OneDrive sharing should be at least as restrictive as SharePoint sharing — otherwise users can route around tenant-level sharing policy by using their personal OneDrive.

**Remediation Action**

```powershell
Set-SPOTenant -OneDriveSharingCapability ExternalUserSharingOnly
```

**Links**
- [CIS Microsoft 365 Foundations Benchmark v6.0.1 - 7.2.4](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
