Office VBA integrates with the Antimalware Scan Interface (AMSI) so Defender can scan macro contents at runtime. Confirm AMSI/Defender is enabled and that the *Macro Runtime Scan Scope* policy is set to *Enable for all documents*.

**Remediation Action**

1. Office Cloud Policy / Intune ADMX > **Macro Runtime Scan Scope** = *Enable for all documents*.
2. Confirm Defender Antivirus is the active AV (or third-party with macro AMSI integration).

**Links**
- [Office VBA + AMSI](https://learn.microsoft.com/en-us/microsoft-365-apps/security/integration-with-amsi)

<!--- Results --->
%TestResult%
