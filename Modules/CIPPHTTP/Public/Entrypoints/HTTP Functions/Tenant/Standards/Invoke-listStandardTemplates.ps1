function Invoke-listStandardTemplates {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Tenant.Standards.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    # Interact with query parameters or the body of the request.
    $ID = $Request.Query.id
    $Table = Get-CippTable -tablename 'templates'
    $Filter = "PartitionKey eq 'StandardsTemplateV2'"
    $Templates = (Get-CIPPAzDataTableEntity @Table -Filter $Filter) | ForEach-Object {
        $JSON = $_.JSON -replace '"Action":', '"action":'
        try {
            $RowKey = $_.RowKey
            $Data = $JSON | ConvertFrom-Json -Depth 100 -ErrorAction SilentlyContinue

        } catch {
            Write-Host "$($RowKey) standard could not be loaded: $($_.Exception.Message)"
            return
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
                            if (-not $IntuneTemplatesCache) {
                                $IntuneTable = Get-CippTable -tablename 'templates'
                                $IntuneFilter = "PartitionKey eq 'IntuneTemplate'"
                                $IntuneTemplatesCache = Get-CIPPAzDataTableEntity @IntuneTable -Filter $IntuneFilter
                            }
                            $PackageName = $Item.'TemplateList-Tags'.value
                            $LiveExpanded = @($IntuneTemplatesCache | Where-Object package -EQ $PackageName | ForEach-Object {
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
