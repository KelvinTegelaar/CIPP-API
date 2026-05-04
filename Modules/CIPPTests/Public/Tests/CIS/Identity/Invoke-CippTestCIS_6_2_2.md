A transport rule that sets SCL to -1 bypasses spam, phish and malware filtering for matching senders. Spoofed messages from those senders pass straight to inboxes.

**Remediation Action**

Audit transport rules for `SetSCL = -1`. Replace with sender-based allow lists in the Tenant Allow/Block List or, better, fix the underlying authentication issue (SPF/DKIM).

**Links**
- [CIS Microsoft 365 Foundations Benchmark v6.0.1 - 6.2.2](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
