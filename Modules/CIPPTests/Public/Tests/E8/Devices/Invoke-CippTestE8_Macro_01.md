Office macros are a major delivery vector for malware. The Defender Attack Surface Reduction rule **Block Win32 API calls from Office macros** stops a macro from invoking the Windows API directly, which is how most macro-based loaders detonate.

**Remediation Action**

1. Intune > Endpoint security > Attack surface reduction > Create policy (Windows 10+, Endpoint detection and response/Attack Surface Reduction Rules).
2. Set *Block Win32 API calls from Office macros* to **Block** (or *Warn*).
3. Assign to all Windows devices.

**Links**
- [ACSC Essential Eight - Configure Microsoft Office macros](https://learn.microsoft.com/en-us/compliance/anz/e8-macro)
- [Defender ASR rules reference](https://learn.microsoft.com/en-us/microsoft-365/security/defender-endpoint/attack-surface-reduction-rules-reference)

<!--- Results --->
%TestResult%
