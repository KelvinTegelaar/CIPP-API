# Legacy Per-User MFA Report

Per-User MFA is an older Microsoft method for enforcing multi-factor authentication that works on a per-account basis. While it does protect accounts, **Microsoft strongly recommends migrating to Conditional Access policies** for a more modern and flexible approach.

Per-User MFA is an all-or-nothing setting — it cannot adapt to context like location, device compliance, or sign-in risk. It can also conflict with Conditional Access policies when both are active, causing duplicate MFA prompts or unexpected sign-in failures.

This report identifies any accounts still relying on Per-User MFA so you can plan a migration to Conditional Access.

**Recommended action**: Migrate identified accounts from Per-User MFA to Conditional Access.

- [Microsoft's guide to migrating from per-user MFA to Conditional Access](https://learn.microsoft.com/en-us/entra/identity/authentication/howto-mfa-getstarted#convert-users-from-per-user-mfa-to-conditional-access-based-mfa)
- [Conditional Access: Require MFA for all users](https://learn.microsoft.com/en-us/entra/identity/conditional-access/howto-conditional-access-policy-all-users-mfa)

<!--- Results --->

%TestResult%
