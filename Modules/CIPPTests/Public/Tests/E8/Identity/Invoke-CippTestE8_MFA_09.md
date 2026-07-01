Number matching defeats MFA fatigue / push-bombing attacks by forcing the user to read a number from the sign-in screen and type it into the Authenticator app. Microsoft made it default in 2023, but tenants that previously customized the policy can still have it disabled or scoped narrowly.

**Remediation Action**

1. Entra ID > Authentication methods > Policies > **Microsoft Authenticator**.
2. Configure features > **Require number matching for push notifications** = Enabled.
3. Set the include target to **All users**.

**Links**
- [How number matching works](https://learn.microsoft.com/en-us/azure/active-directory/authentication/how-to-mfa-number-match)
- [ACSC Essential Eight - MFA](https://learn.microsoft.com/en-us/compliance/anz/e8-mfa)

<!--- Results --->
%TestResult%
