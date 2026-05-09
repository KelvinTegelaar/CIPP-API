SMB1001 (1.10) — Level 5 — disable untrusted Microsoft Office macros. The Intune-managed implementation is Defender Attack Surface Reduction (ASR) rules. The two key rules for SMB1001 1.10 are:

- **Block Win32 API calls from Office macros** — prevents macros from calling Win32 APIs to download/execute payloads.
- **Block all Office applications from creating child processes** — prevents Office from spawning malicious processes.

**Remediation Action**

1. Intune admin centre > Endpoint security > Attack surface reduction > Create policy.
2. Choose Windows > Attack Surface Reduction Rules.
3. Set both Office-macro rules to **Block** (or Audit while validating).
4. Assign to All Devices or a target group.

**Links**
- [SMB1001:2026 Standard](https://dsi.org)
- [Attack Surface Reduction rules reference](https://learn.microsoft.com/en-us/defender-endpoint/attack-surface-reduction-rules-reference)

<!--- Results --->
%TestResult%
