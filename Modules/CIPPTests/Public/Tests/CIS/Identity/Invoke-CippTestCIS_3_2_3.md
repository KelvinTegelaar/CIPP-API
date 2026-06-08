Microsoft 365 Copilot can retrieve, summarize, and generate content from data the user can access across SharePoint, OneDrive, Teams, and Exchange. Without a DLP policy scoped to Copilot interactions, no technical control prevents sensitive information such as PII, financial data, or health records from being surfaced in Copilot-generated responses. At least one enforced DLP policy must include the Microsoft 365 Copilot and Copilot Chat location so sensitive data is intercepted before it is processed by AI-generated responses.

**Remediation Action**

Create or edit a DLP policy in the Microsoft Purview portal to include the Microsoft 365 Copilot and Copilot Chat - All accounts location, add rules for the organization's sensitive information types, and set the policy mode to On (Enable).

**Links**
- [CIS Microsoft 365 Foundations Benchmark v7.0.0 - 3.2.3](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
