Windows PowerShell 2.0 lacks AMSI, ScriptBlockLogging, and the Constrained Language Mode hardening present in 5.1+. Attackers downgrade to v2 to bypass logging. Remove the optional feature.

**Remediation Action**

1. Intune > Compliance / Remediation script: `Disable-WindowsOptionalFeature -Online -FeatureName MicrosoftWindowsPowerShellV2,MicrosoftWindowsPowerShellV2Root -NoRestart`.
2. Verify with `Get-WindowsOptionalFeature -Online -FeatureName MicrosoftWindowsPowerShellV2*`.

**Links**
- [PowerShell v2 deprecation](https://learn.microsoft.com/en-us/powershell/scripting/whats-new/what-s-new-in-powershell-50)

<!--- Results --->
%TestResult%
