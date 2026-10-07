function Get-CIPPBaselineMFAPushAppsState {
    <#
    .SYNOPSIS
        Prepare hook for MFAPushApps: the Azure Multi-Factor Auth Client and Connector
        service principals.
    .DESCRIPTION
        Grades both service principals from the ServicePrincipals cache against the configured
        state. A missing service principal grades enabled, the platform default.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $ServicePrincipals = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'ServicePrincipals')
    if ($ServicePrincipals.Count -eq 0 -and -not (Test-CIPPBaselineCacheCollected -TenantFilter $TenantFilter -Type 'ServicePrincipals')) {
        return @{ Current = $null }
    }
    $Desired = [bool]($Item.Variables.Enabled -eq $true)
    $Client = $ServicePrincipals.Where({ "$($_.appId)" -eq '981f26a1-7f43-403b-a875-f8b09b8cd720' }, 'First')
    $Connector = $ServicePrincipals.Where({ "$($_.appId)" -eq '1f5530b3-261a-47a9-b357-ded261e17918' }, 'First')

    @{
        Expected = [PSCustomObject]@{ mfaClientEnabled = $Desired; mfaConnectorEnabled = $Desired }
        Current  = [PSCustomObject]@{
            mfaClientEnabled    = [bool]($Client.Count -eq 0 -or $Client[0].accountEnabled -ne $false)
            mfaConnectorEnabled = [bool]($Connector.Count -eq 0 -or $Connector[0].accountEnabled -ne $false)
        }
    }
}
