Allowing OneDrive to sync to any device puts company data on personal / unmanaged endpoints. Restrict sync to AD-joined or compliant devices.

**Remediation Action**

```powershell
# Hybrid AD
Set-SPOTenantSyncClientRestriction -Enable -DomainGuids '<dc-guid>'
# Entra-only
Set-SPOTenant -ConditionalAccessPolicy AllowLimitedAccess
```

**Links**
- [CIS Microsoft 365 Foundations Benchmark v6.0.1 - 7.3.2](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
