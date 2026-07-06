function Invoke-listStandardTemplates {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Tenant.Standards.Read
    .DESCRIPTION
        Lists saved standards templates that define sets of standards to apply to tenants.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    # Interact with query parameters or the body of the request.
    $ID = $Request.Query.id
    $Table = Get-CippTable -tablename 'templates'
    $Filter = "PartitionKey eq 'StandardsTemplateV2'"
    $Templates = (Get-CIPPAzDataTableEntity @Table -Filter $Filter) | ForEach-Object {
        $RowKey = $_.RowKey
        $JSON = $_.JSON -replace '"Action":', '"action":'
        try {
            $Data = $JSON | ConvertFrom-Json -Depth 100 -ErrorAction Stop
        } catch {
            try {
                $RepairedJSON = Repair-CippStandardsTemplate -Json $JSON -Reference $RowKey
            } catch {
                Write-LogMessage -headers $Request.Headers -API 'Standards' -message "Standards template '$($RowKey)' was omitted from the response: $($_.Exception.Message)" -Sev 'Error'
                return
            }
            $Data = $RepairedJSON | ConvertFrom-Json -Depth 100
            try {
                $null = Add-CIPPAzDataTableEntity @Table -Entity @{
                    JSON         = "$RepairedJSON"
                    RowKey       = "$RowKey"
                    PartitionKey = 'StandardsTemplateV2'
                    GUID         = "$RowKey"
                } -Force
                Write-LogMessage -headers $Request.Headers -API 'Standards' -message "Standards template '$($RowKey)' contained corrupt data (case-duplicate keys) and was automatically repaired and re-saved." -Sev 'Warning'
            } catch {
                Write-LogMessage -headers $Request.Headers -API 'Standards' -message "Standards template '$($RowKey)' was repaired but could not be re-saved, so it was omitted from the response: $($_.Exception.Message)" -Sev 'Error'
                return
            }
        }
        if ($Data) {
            $Data | Add-Member -NotePropertyName 'GUID' -NotePropertyValue $_.GUID -Force
            $Data | Add-Member -NotePropertyName 'source' -NotePropertyValue $_.Source -Force
            $Data | Add-Member -NotePropertyName 'isSynced' -NotePropertyValue (![string]::IsNullOrEmpty($_.SHA)) -Force

            if (!$Data.excludedTenants) {
                $Data | Add-Member -NotePropertyName 'excludedTenants' -NotePropertyValue @() -Force
            } else {
                if ($Data.excludedTenants -and $Data.excludedTenants -ne 'excludedTenants') {
                    $Data.excludedTenants = @($Data.excludedTenants)
                } else {
                    $Data.excludedTenants = @()
                }
            }

            # Re-expand TemplateList-Tags live so stale addedFields snapshots don't show removed templates
            if ($Data.standards) {
                foreach ($StandardName in $Data.standards.PSObject.Properties.Name) {
                    $StandardConfig = $Data.standards.$StandardName
                    $Items = if ($StandardConfig -is [System.Collections.IEnumerable] -and $StandardConfig -isnot [string]) { $StandardConfig } else { @($StandardConfig) }
                    foreach ($Item in $Items) {
                        if ($Item.'TemplateList-Tags' -and $Item.'TemplateList-Tags'.value) {
                            $PartitionKey = switch ($StandardName) {
                                'ConditionalAccessTemplate' { 'CATemplate' }
                                'IntuneTemplate' { 'IntuneTemplate' }
                                default { 'IntuneTemplate' }
                            }
                            if ($PartitionKey -eq 'CATemplate') {
                                if (-not $CATemplatesCache) {
                                    $CATable = Get-CippTable -tablename 'templates'
                                    $CAFilter = "PartitionKey eq 'CATemplate'"
                                    $CATemplatesCache = Get-CIPPAzDataTableEntity @CATable -Filter $CAFilter
                                }
                                $TemplatesCache = $CATemplatesCache
                            } else {
                                if (-not $IntuneTemplatesCache) {
                                    $IntuneTable = Get-CippTable -tablename 'templates'
                                    $IntuneFilter = "PartitionKey eq 'IntuneTemplate'"
                                    $IntuneTemplatesCache = Get-CIPPAzDataTableEntity @IntuneTable -Filter $IntuneFilter
                                }
                                $TemplatesCache = $IntuneTemplatesCache
                            }
                            $PackageName = $Item.'TemplateList-Tags'.value
                            $LiveExpanded = @($TemplatesCache | Where-Object package -EQ $PackageName | ForEach-Object {
                                    $TplJson = $_.JSON | ConvertFrom-Json -ErrorAction SilentlyContinue
                                    [pscustomobject]@{
                                        GUID        = $_.RowKey
                                        displayName = if ($TplJson.displayName) { $TplJson.displayName } else { $_.RowKey }
                                        name        = if ($TplJson.displayName) { $TplJson.displayName } else { $_.RowKey }
                                    }
                                })
                            if ($Item.'TemplateList-Tags'.addedFields) {
                                $Item.'TemplateList-Tags'.addedFields | Add-Member -NotePropertyName 'templates' -NotePropertyValue $LiveExpanded -Force
                            }
                            if ($Item.'TemplateList-Tags'.rawData) {
                                $Item.'TemplateList-Tags'.rawData | Add-Member -NotePropertyName 'templates' -NotePropertyValue $LiveExpanded -Force
                            }
                            if (-not $Item.'TemplateList-Tags'.addedFields -and -not $Item.'TemplateList-Tags'.rawData) {
                                $Item.'TemplateList-Tags' | Add-Member -NotePropertyName 'addedFields' -NotePropertyValue ([pscustomobject]@{ templates = $LiveExpanded }) -Force
                            }
                        }
                    }
                }
            }

            $Data
        }
    } | Sort-Object -Property templateName

    if ($ID) { $Templates = $Templates | Where-Object GUID -EQ $ID }
    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($Templates)
        })

}
