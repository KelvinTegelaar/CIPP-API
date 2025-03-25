function Invoke-ListExtensionCacheData {
    <#
    .SYNOPSIS
        List Extension Cache Data
    .DESCRIPTION
        This function is used to list the extension cache data.
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Core.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
    $DataTypes = $Request.Query.dataTypes -split ',' ?? $Request.Body.dataTypes ?? 'All'

    $Data = Get-ExtensionCacheData -TenantFilter $TenantFilter

    if ($DataTypes -ne 'All') {
        $Data = $Data | Select-Object $DataTypes
    }

    if (!$Data) {
        $Results = @{}
    }

    $Body = @{
        Results = $Data
    }

    $StatusCode = [HttpStatusCode]::OK

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body | ConvertTo-Json -Compress -Depth 100
            Headers    = @{
                'Content-Type' = 'application/json'
            }
        })
}
