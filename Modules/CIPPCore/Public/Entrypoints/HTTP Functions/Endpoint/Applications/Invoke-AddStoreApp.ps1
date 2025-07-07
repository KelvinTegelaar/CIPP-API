using namespace System.Net

function Invoke-AddStoreApp {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.Application.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    $WinGetApp = $Request.Body
    $AssignTo = $Request.Body.AssignTo

    $WinGetData = [ordered]@{
        '@odata.type'       = '#microsoft.graph.winGetApp'
        'displayName'       = "$($WinGetApp.ApplicationName)"
        'description'       = "$($WinGetApp.description)"
        'packageIdentifier' = "$($WinGetApp.PackageName)"
        'installExperience' = @{
            '@odata.type'  = 'microsoft.graph.winGetAppInstallExperience'
            'runAsAccount' = 'system'
        }
    }

    $Tenants = $Request.Body.selectedTenants.defaultDomainName
    $Results = foreach ($Tenant in $Tenants) {
        try {
            $CompleteObject = [PSCustomObject]@{
                tenant             = $Tenant
                ApplicationName    = $WinGetApp.ApplicationName
                assignTo           = $AssignTo
                InstallationIntent = $Request.Body.InstallationIntent
                type               = 'WinGet'
                IntuneBody         = $WinGetData
            } | ConvertTo-Json -Depth 15
            $Table = Get-CippTable -tablename 'apps'
            $Table.Force = $true
            Add-CIPPAzDataTableEntity @Table -Entity @{
                JSON         = "$CompleteObject"
                RowKey       = "$((New-Guid).GUID)"
                PartitionKey = 'apps'
                status       = 'Not Deployed yet'
            }
            "Successfully added Store App for $($Tenant) to queue."
            Write-LogMessage -headers $Headers -API $APIName -tenant $Tenant -message "Successfully added Store App $($IntuneBody.DisplayName) to queue" -Sev 'Info'
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            "Failed to add Store App for $($Tenant) to queue. Error: $($ErrorMessage.NormalizedError)"
            Write-LogMessage -headers $Headers -API $APIName -tenant $Tenant -message "Failed to add Store App $($IntuneBody.DisplayName) to queue. Error: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        }
    }

    return @{
        StatusCode = [HttpStatusCode]::OK
        Body       = @{ Results = $Results }
    }
}
