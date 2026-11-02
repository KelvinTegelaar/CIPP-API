Code injection is a common technique used by malicious macros to evade detection by piggy-backing on a legitimate process. The ASR rule **Block Office applications from injecting code into other processes** disrupts this.

**Remediation Action**

1. Intune > Endpoint security > Attack surface reduction.
2. Set *Block Office applications from injecting code into other processes* to **Block**.
3. Assign to all Windows devices.

**Links**
- [Defender ASR rules reference](https://learn.microsoft.com/en-us/microsoft-365/security/defender-endpoint/attack-surface-reduction-rules-reference)

<!--- Results --->
%TestResult%
