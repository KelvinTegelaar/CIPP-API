SPF lists the IPs / hosts authorised to send mail for a domain. Without SPF, attackers can spoof mail from your domain and pass at receiving servers.

**Remediation Action**

Publish a TXT record at `<domain>` with `v=spf1 include:spf.protection.outlook.com -all` (or your appropriate include list).

**Links**
- [CIS Microsoft 365 Foundations Benchmark v6.0.1 - 2.1.8](https://www.cisecurity.org/benchmark/microsoft_365)
- [CIPP Domain Analyser](https://docs.cipp.app/user-documentation/tenant/standards/list-standards/domains-analyser)

<!--- Results --->
%TestResult%
