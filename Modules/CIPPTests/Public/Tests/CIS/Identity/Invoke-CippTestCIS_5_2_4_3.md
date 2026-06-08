Requiring users to register for SSPR at sign-in, and to periodically re-confirm their authentication information, keeps recovery contact methods accurate. Stale or attacker-controlled recovery details are a common account-takeover vector, so re-confirmation reduces the window in which they can be abused.

**Remediation Action**

Microsoft Entra admin center > Entra ID > Password reset > Registration > set **Require users to register when signing in** to **Yes** and configure **Number of days before users are asked to re-confirm their authentication information**.

> Manual control — CIPP reports this as Informational for manual review.

**Links**
- [CIS Microsoft 365 Foundations Benchmark v7.0.0 - 5.2.4.3](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
