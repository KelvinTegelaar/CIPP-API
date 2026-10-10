function Invoke-CippTestSecuritySimulation_GuestWithDirectoryRole {
    <#
    .SYNOPSIS
    Security Simulation - Guest account holding a directory role

    .DESCRIPTION
    A guest account that was granted a directory role is used to read the directory and hand privileged access to another account.
    #>
    param($Tenant)

    Invoke-CippSecuritySimulationTest -Tenant $Tenant -ScenarioId 'GuestWithDirectoryRole'
}