function Invoke-CippTestSecuritySimulation_BulkSyncUnmanagedDevice {
    <#
    .SYNOPSIS
    Security Simulation - Bulk sync to an unmanaged device

    .DESCRIPTION
    A compromised user syncs entire document libraries to a personal, unmanaged computer, copying company data off managed systems.
    #>
    param($Tenant)

    Invoke-CippSecuritySimulationTest -Tenant $Tenant -ScenarioId 'BulkSyncUnmanagedDevice'
}