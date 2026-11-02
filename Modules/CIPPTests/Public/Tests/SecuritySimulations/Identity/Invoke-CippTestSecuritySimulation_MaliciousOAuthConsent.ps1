function Invoke-CippTestSecuritySimulation_MaliciousOAuthConsent {
    <#
    .SYNOPSIS
    Security Simulation - Malicious OAuth app consent

    .DESCRIPTION
    A user is tricked into consenting to a malicious application, which then reads mail and files through the granted permissions.
    #>
    param($Tenant)

    Invoke-CippSecuritySimulationTest -Tenant $Tenant -ScenarioId 'MaliciousOAuthConsent'
}