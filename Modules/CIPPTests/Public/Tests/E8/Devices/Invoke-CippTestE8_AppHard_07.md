Email is the #1 phishing vector. The ASR rule **Block executable content from email client and webmail** prevents Outlook (or web browsers viewing webmail) from saving and launching `.exe`/`.scr`/`.js` attachments.

**Remediation Action**

1. Intune > Endpoint security > Attack surface reduction.
2. Set *Block executable content from email client and webmail* to **Block**.
3. Assign to all Windows endpoints.

**Links**
- [ASR rules reference](https://learn.microsoft.com/en-us/microsoft-365/security/defender-endpoint/attack-surface-reduction-rules-reference)

<!--- Results --->
%TestResult%
