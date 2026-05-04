SharePoint's `SharingCapability` controls how external users can be invited. `ExternalUserAndGuestSharing` allows unauthenticated "Anyone" links. CIS recommends restricting to existing or new authenticated guests only.

**Remediation Action**

```powershell
Set-SPOTenant -SharingCapability ExternalUserSharingOnly
```

**Links**
- [CIS Microsoft 365 Foundations Benchmark v6.0.1 - 7.2.3](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
