function Invoke-CippTestSecuritySimulation_MassFileDeletion {
    <#
    .SYNOPSIS
    Security Simulation - Mass file deletion

    .DESCRIPTION
    A compromised user deletes files across SharePoint and OneDrive at scale to disrupt the business or force a ransom.
    #>
    param($Tenant)

    Invoke-CippSecuritySimulationTest -Tenant $Tenant -ScenarioId 'MassFileDeletion'
}