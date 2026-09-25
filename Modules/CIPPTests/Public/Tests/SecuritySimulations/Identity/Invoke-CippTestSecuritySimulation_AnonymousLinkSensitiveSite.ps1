function Invoke-CippTestSecuritySimulation_AnonymousLinkSensitiveSite {
    <#
    .SYNOPSIS
    Security Simulation - Anyone link on a sensitive site

    .DESCRIPTION
    An attacker creates an Anyone link on a sensitive SharePoint site so files can be downloaded without signing in.
    #>
    param($Tenant)

    Invoke-CippSecuritySimulationTest -Tenant $Tenant -ScenarioId 'AnonymousLinkSensitiveSite'
}