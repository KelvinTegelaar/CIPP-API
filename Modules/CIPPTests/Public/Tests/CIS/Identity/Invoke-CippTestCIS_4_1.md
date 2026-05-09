If devices without a compliance policy default to *Compliant*, any unmanaged device satisfies a Conditional Access policy that requires compliance — defeating the purpose. Default to *Not compliant* so the policy must explicitly opt in.

**Remediation Action**

```powershell
Invoke-MgGraphRequest -Method PATCH -Uri 'https://graph.microsoft.com/v1.0/deviceManagement' -Body (@{ settings = @{ secureByDefault = $true } } | ConvertTo-Json)
```

**Links**
- [CIS Microsoft 365 Foundations Benchmark v6.0.1 - 4.1](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
