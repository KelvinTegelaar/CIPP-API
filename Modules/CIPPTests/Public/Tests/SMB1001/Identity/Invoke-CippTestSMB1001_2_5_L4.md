SMB1001 Level 4 / 5 hardens controls 2.5 (MFA on email), 2.6 (MFA on business apps) and 2.9 (MFA where data is stored) with a factor-type prohibition: only Authenticator App, phone-based push, or U2F/FIDO2 may be used. SMS, Voice, Text and Email are explicitly forbidden as second factors and as backup/recovery methods.

**Remediation Action**

```powershell
# Disable weak MFA methods
Update-MgBetaPolicyAuthenticationMethodPolicyAuthenticationMethodConfiguration -Id 'Sms'   -BodyParameter @{state='disabled'}
Update-MgBetaPolicyAuthenticationMethodPolicyAuthenticationMethodConfiguration -Id 'Voice' -BodyParameter @{state='disabled'}
Update-MgBetaPolicyAuthenticationMethodPolicyAuthenticationMethodConfiguration -Id 'Email' -BodyParameter @{state='disabled'}
```

Or use the CIPP standards `standards.DisableSMS`, `standards.DisableVoice`, `standards.DisableEmail`. Pair with `standards.EnableFIDO2` for phishing-resistant factors.

**Links**
- [SMB1001:2026 Standard](https://dsi.org)
- [Manage authentication methods](https://learn.microsoft.com/en-us/entra/identity/authentication/concept-authentication-methods-manage)

<!--- Results --->
%TestResult%
