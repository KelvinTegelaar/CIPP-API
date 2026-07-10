PsExec and WMI process creation are heavily abused for lateral movement. This ASR rule blocks processes spawned through these mechanisms unless explicitly allowed.

**Remediation Action**

1. Intune > Endpoint security > Attack surface reduction.
2. Set *Block process creations originating from PsExec and WMI commands* to **Block**.
3. Note: this may impact some legitimate management tooling — pilot first.

**Links**
- [ASR rules reference](https://learn.microsoft.com/en-us/microsoft-365/security/defender-endpoint/attack-surface-reduction-rules-reference)

<!--- Results --->
%TestResult%
