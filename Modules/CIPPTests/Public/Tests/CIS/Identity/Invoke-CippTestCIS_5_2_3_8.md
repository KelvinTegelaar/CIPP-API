Account lockout protects against brute-force and password spray attacks by locking an account once a set number of failed sign-ins is reached. The lockout threshold defines how many failed attempts are permitted before the account enters a locked-out state. A threshold of 10 or less limits how many password guesses an attacker can make in a given period while avoiding excessive lockouts for legitimate users.

**Remediation Action**

Microsoft Entra > Authentication methods > Password protection: set Lockout threshold to 10 or less.

**Links**
- [CIS Microsoft 365 Foundations Benchmark v7.0.0 - 5.2.3.8](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
