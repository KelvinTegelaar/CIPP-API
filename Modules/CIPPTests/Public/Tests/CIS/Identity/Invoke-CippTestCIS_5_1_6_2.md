By default, guest users can read other users' profiles, group memberships, and many directory objects. The Restricted Guest role removes this directory enumeration ability.

**Remediation Action**

```powershell
Update-MgPolicyAuthorizationPolicy -GuestUserRoleId '2af84b1e-32c8-42b7-82bc-daa82404023b'
```

**Links**
- [CIS Microsoft 365 Foundations Benchmark v6.0.1 - 5.1.6.2](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
