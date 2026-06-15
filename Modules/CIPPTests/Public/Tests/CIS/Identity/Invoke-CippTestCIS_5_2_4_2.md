Requiring two methods to reset a password makes self-service password reset significantly harder to abuse — an attacker who compromises a single factor cannot reset the account password on their own.

**Remediation Action**

Microsoft Entra admin center > Entra ID > Password reset > Authentication methods > set **Number of methods required to reset** to **2**.

> Manual control — CIPP reports this as Informational for manual review.

**Links**
- [CIS Microsoft 365 Foundations Benchmark v7.0.0 - 5.2.4.2](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
