Automatic forwarding to external domains SHALL be disabled.

Disabling automatic forwarding prevents potential data exfiltration scenarios where malicious actors could set up forwarding rules to steal sensitive information. This control ensures that emails cannot be automatically forwarded outside the organization without proper oversight.

**Remediation Action:**

1. Navigate to Exchange Admin Center > Mail flow > Remote domains
2. For each remote domain, disable automatic forwarding:
   - Select the domain
   - Click Edit
   - Set "Allow automatic forwarding" to Off
3. Or use PowerShell:
```powershell
Get-RemoteDomain | Set-RemoteDomain -AutoForwardEnabled $false
```

**Links:**
- [CISA SCubaGear EXO Baseline - MS.EXO.1.1](https://github.com/cisagov/ScubaGear/blob/main/PowerShell/ScubaGear/baselines/exo.md#msexo11v1)
- [Configure remote domain settings](https://learn.microsoft.com/exchange/mail-flow-best-practices/remote-domains/remote-domains)

<!--- Results --->
%TestResult%
