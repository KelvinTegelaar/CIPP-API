function Invoke-AddAppTemplate {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Endpoint.Application.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    if (-not (Test-CippTemplateWriteAccess -PartitionKey 'AppTemplate' -RowKey $Request.Body.GUID)) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::Forbidden; Body = @{ Results = 'Roles limited to specific tenants cannot change or remove shared templates.' } })
    }

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

            # An IntuneBody with an id was read off Graph. Only Office/Edge can rebuild from one;
            # CIPP cannot re-upload a customer's .intunewin, so the template could never deploy.
            $AppType = [string]$App.appType
            $ParsedConfig = $null
            try { $ParsedConfig = $ConfigValue | ConvertFrom-Json -Depth 100 -ErrorAction Stop } catch { $ParsedConfig = $null }
            $IsScriptApp = $AppType -eq 'win32ScriptApp' -and $ParsedConfig.installScript
            if ($ParsedConfig.IntuneBody.id -and $AppType -notin @('officeApp', 'edgeApp') -and -not $IsScriptApp) {
                $AppName = if ($App.appName) { [string]$App.appName } else { [string]$ParsedConfig.ApplicationName }
                throw "'$AppName' is an existing Intune application with uploaded installer content. CIPP application templates are rebuilt from a package or script at deployment, so only Store, Chocolatey, Office, Edge, MSP and Custom (script) applications can be templated."
            }

            if ($AppType -in @('win32PackageApp', 'macOSPackageApp')) {
                $PackageId = [guid]::Empty
                if (-not [guid]::TryParse([string]$ParsedConfig.packageId, [ref]$PackageId)) {
                    throw [System.ArgumentException]::new("Upload the .intunewin package for '$($App.appName)'.")
                }
                # Set by the browser after a fresh upload: assemble the blocks and keep the Detection.xml values beside them.
                $Upload = $ParsedConfig.packageUpload
                if ($Upload) {
                    $BlockCount = [int]$Upload.blockCount
                    if ($BlockCount -lt 1 -or $BlockCount -gt 512 -or -not $Upload.metadata.EncryptionInfo.EncryptionKey) {
                        throw [System.ArgumentException]::new("The uploaded package for '$($App.appName)' is incomplete. Upload it again.")
                    }
                    $BlockIds = foreach ($i in 0..($BlockCount - 1)) { '<Latest>{0}</Latest>' -f [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($i.ToString('000'))) }
                    $null = New-CIPPAzStorageRequest -Service blob -Resource "app-packages/$PackageId/IntunePackage.intunewin" -Method PUT -QueryParams @{ comp = 'blocklist' } -ContentType 'application/xml' -Body ('<?xml version="1.0" encoding="utf-8"?><BlockList>' + ($BlockIds -join '') + '</BlockList>') -ErrorAction Stop
                    $null = New-CIPPAzStorageRequest -Service blob -Resource "app-packages/$PackageId/metadata.json" -Method PUT -ContentType 'application/json' -Body ([string](ConvertTo-Json -Depth 5 -Compress -InputObject $Upload.metadata)) -ErrorAction Stop
                    $ParsedConfig.PSObject.Properties.Remove('packageUpload')
                    $ConfigValue = $ParsedConfig | ConvertTo-Json -Depth 15 -Compress
                }
            }

            $AppsList.Add(@{
                appType = [string]$App.appType
                appName = [string]$App.appName
                config  = [string]$ConfigValue
            })
        }

        $Table = Get-CippTable -tablename 'templates'

        # Upsert: if GUID provided, update existing template
        if ($Body.GUID) {
            $Filter = "PartitionKey eq 'AppTemplate' and RowKey eq '$(ConvertTo-CIPPODataFilterValue -Value $Body.GUID)'"
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
        if ($ExistingEntity) {
            # Packages this edit replaced are deleted once no template uses them.
            Remove-CIPPUnusedAppPackage -PackageIds ([regex]::Matches([string]$ExistingEntity.JSON, 'packageId\\?"\s*:\s*\\?"([0-9a-fA-F-]{36})').ForEach({ $_.Groups[1].Value }))
        }
        Write-LogMessage -headers $Headers -API $APIName -message "Saved app template '$($Body.displayName)' with $AppCount app(s)" -Sev 'Info'
        $Result = "Successfully saved app template '$($Body.displayName)' with $AppCount app(s)"
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to add app template: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
    }

    return ([HttpResponseContext]@{
        StatusCode = $StatusCode
        Body       = @{ Results = $Result }
    })
}
