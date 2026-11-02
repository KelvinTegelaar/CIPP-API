ISM-0843 — application control covers more than `.exe`. Scripts (PS1/JS/VBS), DLLs, MSIs, HTAs, drivers, and control panel applets must all be subject to allowlisting.

**Remediation Action**

1. Author / extend WDAC policy XML to set `Enabled:Audit Mode` off for the additional file rule levels (DLL, Script, MSI, etc.).
2. Deploy via Intune > Endpoint security > Application Control for Business policy XML.

**Links**
- [WDAC policy file rules](https://learn.microsoft.com/en-us/windows/security/application-security/application-control/windows-defender-application-control/design/select-types-of-rules-to-create)

<!--- Results --->
%TestResult%
