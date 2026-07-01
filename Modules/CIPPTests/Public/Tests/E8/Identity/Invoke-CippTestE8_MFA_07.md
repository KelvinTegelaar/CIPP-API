A Conditional Access policy can require phishing-resistant MFA, but it only takes effect once each privileged user has actually registered such a method (FIDO2 key, Windows Hello, certificate, or device-bound passkey). This test enumerates privileged role members whose `methodsRegistered` list does not yet include a phishing-resistant method.

**Remediation Action**

1. Issue FIDO2 keys (or enable Windows Hello / certificate auth / passkeys) to each privileged user.
2. Have them register the method at https://aka.ms/mysecurityinfo before the Conditional Access policy is enforced.
3. Re-run this test once registrations complete.

**Links**
- [ACSC Essential Eight - MFA](https://learn.microsoft.com/en-us/compliance/anz/e8-mfa)
- [User registration details API](https://learn.microsoft.com/en-us/graph/api/resources/userregistrationdetails)

<!--- Results --->
%TestResult%
