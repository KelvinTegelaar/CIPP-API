Bring-Your-Own-Vulnerable-Driver (BYOVD) is a common kernel-privilege escalation technique. This ASR rule blocks Microsoft's curated list of known-bad signed drivers from loading.

**Remediation Action**

1. Intune > Endpoint security > Attack surface reduction.
2. Set *Block abuse of exploited vulnerable signed drivers* to **Block**.
3. Pair with the Microsoft vulnerable driver blocklist (Smart App Control / WDAC).

**Links**
- [Microsoft recommended driver block rules](https://learn.microsoft.com/en-us/windows/security/application-security/application-control/microsoft-recommended-driver-block-rules)

<!--- Results --->
%TestResult%
