If a compromised user can read their own device's BitLocker recovery key, an attacker with stolen credentials can also unlock the disk on a stolen device.

**Remediation Action**

```powershell
Update-MgPolicyAuthorizationPolicy -DefaultUserRolePermissions @{ AllowedToReadBitLockerKeysForOwnedDevice = $false }
```

**Links**
- [CIS Microsoft 365 Foundations Benchmark v6.0.1 - 5.1.4.6](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
