Email scanning SHALL be capable of reviewing emails after delivery.

Zero-hour Auto Purge (ZAP) provides post-delivery protection by retroactively detecting and removing malicious emails that were initially deemed safe. This is crucial because malware signatures and threat intelligence are constantly updated, and emails that were safe at delivery time may later be identified as malicious.

**Remediation Action:**

1. Navigate to Microsoft 365 Defender portal > Email & collaboration > Policies & rules > Threat policies > Anti-malware
2. Select each malware filter policy
3. Under "Protection settings":
   - Enable "Enable zero-hour auto purge (ZAP) for malware"
4. Or use PowerShell:
```powershell
Set-MalwareFilterPolicy -Identity "Default" -ZapEnabled $true
```

**Links:**
- [CISA SCubaGear EXO Baseline - MS.EXO.10.3](https://github.com/cisagov/ScubaGear/blob/main/PowerShell/ScubaGear/baselines/exo.md#msexo103v1)
- [Zero-hour auto purge (ZAP) in Microsoft Defender for Office 365](https://learn.microsoft.com/microsoft-365/security/office-365-security/zero-hour-auto-purge)

<!--- Results --->
%TestResult%
