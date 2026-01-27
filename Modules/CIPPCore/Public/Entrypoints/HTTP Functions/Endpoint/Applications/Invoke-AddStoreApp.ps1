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


    $WinGetApp = $Request.Body
    $assignTo = $Request.Body.AssignTo -eq 'customGroup' ? $Request.Body.CustomGroup : $Request.Body.AssignTo

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

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })

}
