function Initialize-CippTestSuiteCopilotReadiness {
    <#
    .SYNOPSIS
        Reads the licensed users once for the whole CopilotReadiness suite before Invoke-CIPPTestCollection runs it.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Tenant)

    $script:CippCopilotReadinessUsers = $null
    $script:CippCopilotReadinessUsers = Get-CippCopilotReadinessUsers -Tenant $Tenant
}
