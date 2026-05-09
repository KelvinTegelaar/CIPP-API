SMB1001 (2.1) — Level 1+ — requires strong password hygiene including unique passphrases that have not appeared in data breaches. Entra ID Password Protection ships a global banned-password list maintained by Microsoft and lets you add an organisation-specific custom list (company name, product names, common local terms). The custom list requires Entra ID Premium P1 or P2.

**Remediation Action**

```powershell
# Configure custom banned passwords in Entra Portal
# https://entra.microsoft.com > Protection > Authentication methods > Password protection
# Enable "Enforce custom list" and add 4-16 character organisation-specific terms.
```

Or use the CIPP standard `standards.CustomBannedPasswordList` to deploy this across tenants.

**Links**
- [SMB1001:2026 Standard](https://dsi.org)
- [Microsoft Entra Password Protection](https://learn.microsoft.com/en-us/entra/identity/authentication/concept-password-ban-bad)

<!--- Results --->
%TestResult%
