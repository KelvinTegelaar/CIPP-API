Allowing users to access the Office Store and start trials lets non-vetted add-ins enter the tenant. Trial subscriptions can also bypass procurement and create unmanaged data sprawl.

**Remediation Action**

```powershell
$body = @{ Settings = @{ isAppAndServicesTrialEnabled = $false; isOfficeStoreEnabled = $false } } | ConvertTo-Json
Invoke-MgGraphRequest -Method PATCH -Uri 'https://graph.microsoft.com/beta/admin/appsAndServices' -Body $body
```

**Links**
- [CIS Microsoft 365 Foundations Benchmark v6.0.1 - 1.3.4](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
