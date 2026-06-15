SMTP AUTH SHALL be disabled in Exchange Online.

SMTP AUTH is a legacy authentication protocol that doesn't support modern security features like multi-factor authentication. Disabling SMTP AUTH reduces the attack surface and forces applications to use more secure authentication methods like OAuth 2.0.

**Remediation Action:**

1. Navigate to Exchange Admin Center > Mail flow > SMTP AUTH
2. Disable SMTP AUTH for all users or specific users
3. Or use PowerShell to disable organization-wide:
```powershell
Set-TransportConfig -SmtpClientAuthenticationDisabled $true
```
4. Or disable per-mailbox:
```powershell
Set-CASMailbox -Identity user@domain.com -SmtpClientAuthenticationDisabled $true
```

**Links:**
- [CISA SCubaGear EXO Baseline - MS.EXO.5.1](https://github.com/cisagov/ScubaGear/blob/main/PowerShell/ScubaGear/baselines/exo.md#msexo51v1)
- [Disable SMTP AUTH](https://learn.microsoft.com/exchange/clients-and-mobile-in-exchange-online/authenticated-client-smtp-submission)

<!--- Results --->
%TestResult%
