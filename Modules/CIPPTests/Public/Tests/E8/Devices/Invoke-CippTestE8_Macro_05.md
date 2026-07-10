Outlook is a frequent first-stage delivery vector. The ASR rule **Block Office communication application from creating child processes** blocks Outlook from spawning PowerShell, cmd, or scripting hosts — a key step in many phishing kill-chains.

**Remediation Action**

1. Intune > Endpoint security > Attack surface reduction.
2. Set *Block Office communication application from creating child processes* to **Block**.
3. Assign to all Windows devices.

**Links**
- [Defender ASR rules reference](https://learn.microsoft.com/en-us/microsoft-365/security/defender-endpoint/attack-surface-reduction-rules-reference)

<!--- Results --->
%TestResult%
