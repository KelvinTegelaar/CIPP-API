Microsoft Forms is regularly abused for credential phishing. Internal phishing scanning detects forms that ask for sensitive information (passwords, MFA codes) and blocks delivery.

**Remediation Action**

PATCH `https://graph.microsoft.com/beta/admin/forms` with `{ "settings": { "isInOrgFormsPhishingScanEnabled": true } }`.

**Links**
- [CIS Microsoft 365 Foundations Benchmark v6.0.1 - 1.3.5](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
