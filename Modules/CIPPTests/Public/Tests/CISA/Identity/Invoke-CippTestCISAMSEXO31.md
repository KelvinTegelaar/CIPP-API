DKIM SHOULD be enabled for all domains.

DomainKeys Identified Mail (DKIM) adds a digital signature to outgoing email messages, allowing receiving mail servers to verify that the email actually came from your domain and wasn't altered in transit. This helps prevent email spoofing and improves email deliverability.

**Remediation Action:**

1. Navigate to Microsoft 365 Defender portal > Email & collaboration > Policies & rules > Threat policies > DKIM
2. For each domain:
   - Select the domain
   - Click "Create DKIM keys" if not already created
   - Publish the CNAME records to DNS
   - Enable DKIM signing
3. Or use PowerShell:
```powershell
# Create DKIM signing configuration
New-DkimSigningConfig -DomainName "contoso.com" -Enabled $true

# Enable existing DKIM configuration
Set-DkimSigningConfig -Identity "contoso.com" -Enabled $true
```

**Links:**
- [CISA SCubaGear EXO Baseline - MS.EXO.3.1](https://github.com/cisagov/ScubaGear/blob/main/PowerShell/ScubaGear/baselines/exo.md#msexo31v1)
- [Use DKIM to validate outbound email](https://learn.microsoft.com/microsoft-365/security/office-365-security/email-authentication-dkim-configure)

<!--- Results --->
%TestResult%
