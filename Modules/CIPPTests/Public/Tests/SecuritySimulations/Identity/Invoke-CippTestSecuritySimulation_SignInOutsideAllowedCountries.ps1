function Invoke-CippTestSecuritySimulation_SignInOutsideAllowedCountries {
    <#
    .SYNOPSIS
    Security Simulation - Sign-in from outside allowed countries

    .DESCRIPTION
    An attacker signs in from a country the organization never operates in and reaches a user's mailbox and files.
    #>
    param($Tenant)

    Invoke-CippSecuritySimulationTest -Tenant $Tenant -ScenarioId 'SignInOutsideAllowedCountries'
}