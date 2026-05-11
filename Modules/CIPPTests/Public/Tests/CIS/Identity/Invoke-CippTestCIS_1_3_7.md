Third-party providers (Dropbox, Box, Google Drive) integrated with Microsoft 365 on the web allow data to leave the tenant boundary. Disable the integration unless explicitly required.

**Remediation Action**

Disable the `Microsoft 365 on the web` service principal (appId `c1f33bc0-bdb4-4248-ba9b-096807ddb43e`):

```powershell
Update-MgServicePrincipal -ServicePrincipalId <id> -AccountEnabled:$false
```

**Links**
- [CIS Microsoft 365 Foundations Benchmark v6.0.1 - 1.3.7](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
