Macro-based attacks routinely launch PowerShell, cmd, or wscript as a child of Word/Excel. The ASR rule **Block all Office applications from creating child processes** blocks this entire technique class.

**Remediation Action**

1. Intune > Endpoint security > Attack surface reduction.
2. Set *Block all Office applications from creating child processes* to **Block**.
3. Assign to all Windows devices.

**Links**
- [Defender ASR rules reference](https://learn.microsoft.com/en-us/microsoft-365/security/defender-endpoint/attack-surface-reduction-rules-reference)

<!--- Results --->
%TestResult%
