Insurers ask whether email is filtered for phishing and malware. This check passes when Defender for Office 365 Safe Links and Safe Attachments are both enabled, or when mail is delivered through a third-party gateway. Exchange Online Protection alone is reported for review, because every tenant has it.

**Remediation Action**

1. Enable the Standard or Strict preset security policy in Defender for Office 365, or create Safe Links and Safe Attachments policies that cover all recipients.
2. If a third-party gateway filters mail, make sure the domain's MX record points to it.

<!--- Results --->
%TestResult%
