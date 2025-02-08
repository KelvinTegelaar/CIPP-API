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
    Write-LogMessage -headers $Request.Headers -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    Write-Host 'PowerShell HTTP trigger function processed a request.'
    $WinGetApp = $request.body
    if ($ChocoApp.InstallAsSystem) { 'system' } else { 'user' }
    $assignTo = $Request.body.AssignTo
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
    $Results = foreach ($Tenant in $tenants) {
        try {
            $CompleteObject = [PSCustomObject]@{
                tenant             = $tenant
                Applicationname    = $WinGetApp.ApplicationName
                assignTo           = $assignTo
                InstallationIntent = $request.body.InstallationIntent
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
            Write-LogMessage -headers $Request.Headers -API $APINAME -tenant $tenant -message "Successfully added Store App $($intunebody.Displayname) to queue" -Sev 'Info'
        } catch {
            Write-LogMessage -headers $Request.Headers -API $APINAME -tenant $tenant -message "Failed to add Store App $($intunebody.Displayname) to queue" -Sev 'Error'
            "Failed added Store App for $($Tenant) to queue"
        }
    }

    $body = [pscustomobject]@{'Results' = $results }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })

}
