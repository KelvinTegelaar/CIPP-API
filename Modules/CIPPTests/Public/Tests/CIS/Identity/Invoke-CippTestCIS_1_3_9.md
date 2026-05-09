Microsoft Bookings can be abused to create authoritative-looking external email addresses (e.g. a compromised user creating a fake `ceo@<tenant>.com` Bookings mailbox to impersonate the CEO). CIS recommends restricting Bookings to a small set of approved users.

**Remediation Action**

Restrict via the default OWA policy:

```powershell
Set-OwaMailboxPolicy "OwaMailboxPolicy-Default" -BookingsMailboxCreationEnabled:$false
```

Or disable organisation-wide (more restrictive, also passes):

```powershell
Set-OrganizationConfig -BookingsEnabled $false
```

**Links**
- [CIS Microsoft 365 Foundations Benchmark v6.0.1 - 1.3.9](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
