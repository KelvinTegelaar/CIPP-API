.NET Framework 3.5 (which carries .NET 2.0 and 3.0 runtimes) lacks modern hardening — no AMSI, no per-app strong name verification — and is a frequent ROP gadget source. Remove it from SOEs.

**Remediation Action**

1. Intune > Endpoint security > Compliance policies > custom compliance script: fail when `(Get-WindowsOptionalFeature -Online -FeatureName 'NetFx3').State -eq 'Enabled'`.
2. Remediate via PSscript: `Disable-WindowsOptionalFeature -Online -FeatureName NetFx3`.

**Links**
- [.NET Framework lifecycle](https://learn.microsoft.com/en-us/lifecycle/products/microsoft-net-framework)

<!--- Results --->
%TestResult%
