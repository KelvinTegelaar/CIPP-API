Office macros frequently drop and execute payloads. The ASR rule **Block Office applications from creating executable content** prevents Word/Excel/PowerPoint from writing `.exe`/`.dll`/`.scr`/macros that drop binaries to disk.

**Remediation Action**

1. Intune > Endpoint security > Attack surface reduction.
2. Set *Block Office applications from creating executable content* to **Block** (or *Warn*).
3. Assign to all Windows devices.

**Links**
- [Defender ASR rules reference](https://learn.microsoft.com/en-us/microsoft-365/security/defender-endpoint/attack-surface-reduction-rules-reference)

<!--- Results --->
%TestResult%
