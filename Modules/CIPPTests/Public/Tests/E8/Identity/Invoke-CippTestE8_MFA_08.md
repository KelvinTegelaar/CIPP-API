Essential Eight Maturity Level 3 extends the phishing-resistant MFA requirement from privileged users to **all** users. Every enabled member account must have at least one phishing-resistant method (FIDO2, Windows Hello for Business, certificate-based authentication, or device-bound passkey) registered.

**Remediation Action**

1. Roll out FIDO2 security keys, Windows Hello for Business, or device-bound passkeys to all staff.
2. Run a registration campaign — make sure each user registers at least one phishing-resistant method.
3. Once coverage is complete, enforce via a tenant-wide Conditional Access policy with the *Phishing-resistant MFA* authentication strength.

**Links**
- [ACSC Essential Eight - MFA](https://learn.microsoft.com/en-us/compliance/anz/e8-mfa)
- [Plan a passwordless authentication deployment](https://learn.microsoft.com/en-us/azure/active-directory/authentication/howto-authentication-passwordless-deployment)

<!--- Results --->
%TestResult%
