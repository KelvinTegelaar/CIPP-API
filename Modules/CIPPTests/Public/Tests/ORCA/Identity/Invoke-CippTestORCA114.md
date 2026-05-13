Anti-spam policies should not have IP addresses configured in the allow list. IP-based allow lists can be exploited by attackers who use compromised or shared infrastructure, and they bypass important security controls. Instead of using IP allow lists, implement proper email authentication (SPF, DKIM, DMARC) and use sender-based allow lists only when absolutely necessary.

**Remediation action**

- [Configure anti-spam policies in EOP](https://learn.microsoft.com/microsoft-365/security/office-365-security/anti-spam-policies-configure)
- [Configure the connection filter policy](https://learn.microsoft.com/microsoft-365/security/office-365-security/connection-filter-policies-configure)
- [Create safe sender lists in EOP](https://learn.microsoft.com/microsoft-365/security/office-365-security/create-safe-sender-lists-in-office-365)

<!--- Results --->
%TestResult%
