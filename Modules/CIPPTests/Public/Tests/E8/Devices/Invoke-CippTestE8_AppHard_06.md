Credential theft from `lsass.exe` (e.g. Mimikatz) is the foundation of most lateral movement attacks. The ASR rule blocks reads against LSASS memory by untrusted processes.

**Remediation Action**

1. Intune > Endpoint security > Attack surface reduction.
2. Set *Block credential stealing from the Windows local security authority subsystem* to **Block**.
3. Assign to all Windows endpoints; pair with Credential Guard.

**Links**
- [ASR rules reference](https://learn.microsoft.com/en-us/microsoft-365/security/defender-endpoint/attack-surface-reduction-rules-reference)

<!--- Results --->
%TestResult%
