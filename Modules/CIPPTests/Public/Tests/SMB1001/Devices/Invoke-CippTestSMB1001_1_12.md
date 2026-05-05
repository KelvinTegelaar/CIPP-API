SMB1001 (1.12) — Level 3 + Level 5 — implement Endpoint Detection and Response (EDR). At Level 5 the EDR must be paired with a Managed Detection and Response (MDR) service with a defined SLA. The Microsoft 365 implementation is Microsoft Defender for Endpoint, deployed via Intune onboarding plus an Endpoint security > EDR configuration policy.

The MDR contractual relationship is verified separately to a Dynamic Standard Certifier (it is an operational control, not a tenant config).

**Remediation Action**

1. Microsoft 365 Defender > Settings > Endpoints > Onboarding — generate the onboarding package.
2. Intune admin centre > Endpoint security > Endpoint detection and response > Create policy.
3. Choose "Auto-configure from MDE connector" so devices use the connector's configuration.
4. Assign to All Devices.

Use CIPP `standards.IntuneTemplate` with an EDR template to deploy across tenants.

**Links**
- [SMB1001:2026 Standard](https://dsi.org)
- [Onboard devices to Defender for Endpoint with Intune](https://learn.microsoft.com/en-us/defender-endpoint/configure-endpoints-mdm)

<!--- Results --->
%TestResult%
