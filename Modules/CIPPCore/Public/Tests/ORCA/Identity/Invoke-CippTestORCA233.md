Custom domains should have their MX records pointed directly at Exchange Online Protection (EOP) or use enhanced filtering with inbound connectors. This ensures that all email security features function properly, including SPF, DKIM, and DMARC validation. When mail flows through third-party services without proper configuration, important security signals can be lost.

**Remediation action**

- [Mail flow best practices for Exchange Online and Microsoft 365](https://learn.microsoft.com/exchange/mail-flow-best-practices/mail-flow-best-practices)
- [Enhanced filtering for connectors in Exchange Online](https://learn.microsoft.com/exchange/mail-flow-best-practices/use-connectors-to-configure-mail-flow/enhanced-filtering-for-connectors)
<!--- Results --->
%TestResult%
