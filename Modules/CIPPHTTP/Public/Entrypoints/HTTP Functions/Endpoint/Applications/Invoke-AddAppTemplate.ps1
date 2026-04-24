function Invoke-AddAppTemplate {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Endpoint.Application.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    try {
        $Body = $Request.Body
        if (!$Body.displayName) { throw 'You must enter a display name' }

        $RawApps = $Body.apps
        if (!$RawApps -or ($RawApps | Measure-Object).Count -eq 0) {
            throw 'You must add at least one application'
        }

        $AppsList = [System.Collections.Generic.List[hashtable]]::new()
        foreach ($App in @($RawApps)) {
            $ConfigValue = if ($App.config -is [string]) { $App.config } else { $App.config | ConvertTo-Json -Depth 15 -Compress }
            $AppsList.Add(@{
                appType = [string]$App.appType
                appName = [string]$App.appName
                config  = [string]$ConfigValue
            })
        }

        $Table = Get-CippTable -tablename 'templates'

        # Upsert: if GUID provided, update existing template
        if ($Body.GUID) {
            $Filter = "PartitionKey eq 'AppTemplate' and RowKey eq '$($Body.GUID)'"
            $ExistingEntity = Get-CIPPAzDataTableEntity @Table -Filter $Filter
        }

        if ($ExistingEntity) {
            $GUID = $ExistingEntity.RowKey
        } else {
            $GUID = (New-Guid).GUID
        }

        $AppsJSON = ConvertTo-Json -InputObject @($AppsList.ToArray()) -Depth 15 -Compress -AsArray
        $TemplateJSON = ConvertTo-Json -InputObject @{
            Displayname = $Body.displayName
            Description = $Body.description ?? ''
            GUID        = $GUID
        } -Depth 15 -Compress
        $TemplateJSON = $TemplateJSON.TrimEnd('}') + ',"Apps":' + $AppsJSON + '}'

        $Table.Force = $true
        Add-CIPPAzDataTableEntity @Table -Entity @{
            JSON         = [string]$TemplateJSON
            RowKey       = [string]$GUID
            PartitionKey = 'AppTemplate'
        }

        $AppCount = $AppsList.Count
        Write-LogMessage -headers $Headers -API $APIName -message "Saved app template '$($Body.displayName)' with $AppCount app(s)" -Sev 'Info'
        $Result = "Successfully saved app template '$($Body.displayName)' with $AppCount app(s)"
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to add app template: $($ErrorMessage.NormalizedMessage)"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
        StatusCode = $StatusCode
        Body       = @{ Results = $Result }
    })
}
