Obfuscated PowerShell, JavaScript, and VBScript are hallmarks of malware delivery. The ASR rule blocks scripts that exhibit obfuscation patterns from running.

**Remediation Action**

1. Intune > Endpoint security > Attack surface reduction.
2. Set *Block execution of potentially obfuscated scripts* to **Block** (start with *Warn* if you suspect false positives).

**Links**
- [ASR rules reference](https://learn.microsoft.com/en-us/microsoft-365/security/defender-endpoint/attack-surface-reduction-rules-reference)

<!--- Results --->
%TestResult%
