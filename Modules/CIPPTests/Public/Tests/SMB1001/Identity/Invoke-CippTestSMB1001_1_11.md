SMB1001 (1.11) — Level 5 — requires regular penetration testing, vulnerability scans, and social-engineering simulations. These are operational activities executed outside the Microsoft 365 tenant and cannot be verified automatically. This test is **informational**: evidence the testing programme to your Dynamic Standard Certifier directly.

**Remediation Action**

1. Engage a third-party vendor for annual external penetration testing.
2. Schedule quarterly vulnerability scans of public-facing services.
3. Run an ongoing social-engineering simulation programme (KnowBe4, Hoxhunt, Cofense). Configure a Phishing Simulation Override Policy in Defender (Microsoft 365 Defender > Policies > Advanced delivery) to whitelist the vendor's delivery domains and IPs.
4. Maintain a remediation register that links findings to fixes.

**Links**
- [SMB1001:2026 Standard](https://dsi.org)
- [Configure third-party phishing simulations in Defender](https://learn.microsoft.com/en-us/defender-office-365/advanced-delivery-policy-configure)

<!--- Results --->
%TestResult%
