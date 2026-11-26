Insurers ask whether sensitive data is encrypted in transit. For Microsoft 365 this check covers email: whether SMTP AUTH is disabled, whether MTA-STS is enforced on the tenant's mail domains, and whether connectors and mail flow rules require TLS or message encryption. Other systems are outside what the tenant can show.

**Remediation Action**

1. Disable SMTP AUTH for the organisation and allow it only on mailboxes that need it.
2. Publish an MTA-STS policy in enforce mode for each mail domain.
3. Use message encryption for mail that carries sensitive data.

<!--- Results --->
%TestResult%
