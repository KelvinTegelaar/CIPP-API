At a minimum, click-to-run files SHOULD be blocked (e.g., .exe, .cmd, and .vbe).

Blocking executable file types prevents users from receiving and potentially executing malicious files through email. These file types are commonly used in malware attacks and social engineering campaigns.

**Remediation Action:**

1. Navigate to Microsoft 365 Defender portal > Email & collaboration > Policies & rules > Threat policies > Anti-malware
2. Select the malware filter policy to edit
3. Under "Protection settings":
   - Enable "Enable the common attachments filter"
   - Ensure the blocked file types include at minimum: cmd, exe, vbe
4. Or use PowerShell:
```powershell
Set-MalwareFilterPolicy -Identity "Default" -EnableFileFilter $true -FileTypes @("ace","ani","app","cab","docm","exe","jar","reg","scr","vbe","vbs","cmd","bat","com","cpl","dll","exe","hta","inf","ins","isp","js","jse","lib","lnk","mde","msc","msp","mst","pif","scr","sct","shb","sys","vb","vbe","vbs","vxd","wsc","wsf","wsh")
```

**Links:**
- [CISA SCubaGear EXO Baseline - MS.EXO.9.5](https://github.com/cisagov/ScubaGear/blob/main/PowerShell/ScubaGear/baselines/exo.md#msexo95v1)
- [Configure anti-malware policies](https://learn.microsoft.com/microsoft-365/security/office-365-security/anti-malware-protection-configure)

<!--- Results --->
%TestResult%
