SMB1001 (2.12) — Level 2+ — configure SPF, DKIM, and DMARC on every domain used to send organisational email. Level 3 prescribes DMARC `p=reject` or `p=quarantine` with annual review. SPF prevents domain spoofing, DKIM cryptographically signs outgoing mail, and DMARC tells receivers what to do when SPF/DKIM fail.

**Remediation Action**

```powershell
# DKIM
New-DkimSigningConfig -DomainName contoso.com -KeySize 2048 -Enabled $true
# SPF (DNS TXT)
"v=spf1 include:spf.protection.outlook.com -all"
# DMARC (DNS TXT at _dmarc.contoso.com)
"v=DMARC1; p=reject; rua=mailto:dmarc@contoso.com"
```

Use the CIPP standards `standards.AddDKIM`, `standards.RotateDKIM`, and `standards.AddDMARCToMOERA` to automate.

**Links**
- [SMB1001:2026 Standard](https://dsi.org)
- [Set up SPF, DKIM and DMARC for Microsoft 365](https://learn.microsoft.com/en-us/defender-office-365/email-authentication-about)

<!--- Results --->
%TestResult%
