ISM-0445 — privileged users are issued dedicated privileged accounts that are separate from their unprivileged identities. In a Microsoft 365 tenant the strongest implementation is **cloud-only** privileged accounts so the on-premises directory cannot compromise privileged identities. This test fails any privileged role member whose `onPremisesSyncEnabled` is true.

**Remediation Action**

1. Create a dedicated cloud-only account on the `<tenant>.onmicrosoft.com` domain for each administrator.
2. Reassign privileged roles to the cloud-only account.
3. Remove privileged role assignments from synced accounts.

**Links**
- [ACSC Essential Eight - Restrict Administrative Privileges](https://learn.microsoft.com/en-us/compliance/anz/e8-admin)
- [ISM-0445](https://www.cyber.gov.au/ism)

<!--- Results --->
%TestResult%
