using namespace System.Net

Function Invoke-AddStoreApp {
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
    $assignTo = $Request.body.AssignTo

    if ($ChocoApp.InstallAsSystem) { 'system' } else { 'user' }
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

    $Tenants = $Request.body.selectedTenants.defaultDomainName
    $Results = foreach ($Tenant in $Tenants) {
        try {
            $CompleteObject = [PSCustomObject]@{
                tenant             = $Tenant
                ApplicationName    = $WinGetApp.ApplicationName
                assignTo           = $assignTo
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
            Write-LogMessage -headers $Headers -API $APIName -tenant $tenant -message "Successfully added Store App $($IntuneBody.DisplayName) to queue" -Sev 'Info'
        } catch {
            Write-LogMessage -headers $Headers -API $APIName -tenant $tenant -message "Failed to add Store App $($IntuneBody.DisplayName) to queue" -Sev 'Error'
            "Failed to add Store App for $($Tenant) to queue"
        }
    }

    $body = [pscustomobject]@{'Results' = $Results }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })

}
