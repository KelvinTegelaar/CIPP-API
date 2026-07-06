Removable media is a common malware vector. This ASR rule blocks unsigned/untrusted executables from launching when run from USB drives.

**Remediation Action**

1. Intune > Endpoint security > Attack surface reduction.
2. Set *Block untrusted and unsigned processes that run from USB* to **Block**.
3. Pair with a removable storage access policy if USB is not required.

**Links**
- [ASR rules reference](https://learn.microsoft.com/en-us/microsoft-365/security/defender-endpoint/attack-surface-reduction-rules-reference)

<!--- Results --->
%TestResult%
