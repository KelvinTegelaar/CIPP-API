function Invoke-ListIntuneTemplates {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Endpoint.MEM.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $Table = Get-CippTable -tablename 'templates'
    $Imported = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'settings'"
    if ($Imported.IntuneTemplate -ne $true) {
        $Templates = Get-ChildItem (Join-Path $env:CIPPRootPath 'Config\*.IntuneTemplate.json') | ForEach-Object {
            $Entity = @{
                JSON         = "$(Get-Content $_)"
                RowKey       = "$($_.name)"
                PartitionKey = 'IntuneTemplate'
                GUID         = "$($_.name)"
            }
            Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force
        }
        Add-CIPPAzDataTableEntity @Table -Entity @{
            IntuneTemplate = $true
            RowKey         = 'IntuneTemplate'
            PartitionKey   = 'settings'
        } -Force
    }
    #List new policies
    $Table = Get-CippTable -tablename 'templates'
    $Filter = "PartitionKey eq 'IntuneTemplate'"
    $RawTemplates = (Get-CIPPAzDataTableEntity @Table -Filter $Filter)
    if ($Request.query.View) {
        $Templates = $RawTemplates | ForEach-Object {
            try {
                $JSONData = $_.JSON | ConvertFrom-Json -Depth 100 -ErrorAction SilentlyContinue
                $data = $JSONData.RAWJson | ConvertFrom-Json -Depth 100 -ErrorAction SilentlyContinue
                $data | Add-Member -NotePropertyName 'displayName' -NotePropertyValue $JSONData.Displayname -Force
                $data | Add-Member -NotePropertyName 'description' -NotePropertyValue $JSONData.Description -Force
                $data | Add-Member -NotePropertyName 'Type' -NotePropertyValue $JSONData.Type -Force
                $data | Add-Member -NotePropertyName 'GUID' -NotePropertyValue $_.RowKey -Force
                $data | Add-Member -NotePropertyName 'package' -NotePropertyValue $_.Package -Force
                $data | Add-Member -NotePropertyName 'isSynced' -NotePropertyValue (![string]::IsNullOrEmpty($_.SHA)) -Force
                $data | Add-Member -NotePropertyName 'source' -NotePropertyValue $_.Source -Force
                $data | Add-Member -NotePropertyName 'reusableSettings' -NotePropertyValue $JSONData.ReusableSettings -Force
                $data
            } catch {

            }

        } | Sort-Object -Property displayName

        # Build a lookup of which standards templates reference each Intune template (by GUID or package)
        $UsageByGuid = @{}
        $UsageByPackage = @{}
        $StdTemplates = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'StandardsTemplateV2'"
        foreach ($StdRaw in $StdTemplates) {
            try {
                $StdData = $StdRaw.JSON | ConvertFrom-Json -Depth 100 -ErrorAction SilentlyContinue
                if (-not $StdData -or -not $StdData.standards) { continue }
                $IsDrift = $StdData.type -eq 'drift'
                $StdInfo = [pscustomobject]@{
                    templateName = $StdData.templateName
                    templateId   = $StdRaw.RowKey
                    isDrift      = $IsDrift
                    cippLink     = "/tenant/standards/templates/template?id=$($StdRaw.RowKey)$(if ($IsDrift) { '&type=drift' })"
                }
                $IntuneEntries = $StdData.standards.IntuneTemplate
                if (-not $IntuneEntries) { continue }
                $Items = if ($IntuneEntries -is [System.Collections.IEnumerable] -and $IntuneEntries -isnot [string]) { $IntuneEntries } else { @($IntuneEntries) }
                foreach ($Item in $Items) {
                    if ($Item.TemplateList.value) {
                        $Guid = $Item.TemplateList.value
                        if (-not $UsageByGuid.ContainsKey($Guid)) { $UsageByGuid[$Guid] = [System.Collections.Generic.List[object]]::new() }
                        $UsageByGuid[$Guid].Add($StdInfo)
                    }
                    if ($Item.'TemplateList-Tags'.value) {
                        $Pkg = $Item.'TemplateList-Tags'.value
                        if (-not $UsageByPackage.ContainsKey($Pkg)) { $UsageByPackage[$Pkg] = [System.Collections.Generic.List[object]]::new() }
                        $UsageByPackage[$Pkg].Add($StdInfo)
                    }
                }
            } catch {}
        }

        # Attach usage list to each Intune template
        foreach ($Tpl in $Templates) {
            $Usage = [System.Collections.Generic.List[object]]::new()
            if ($Tpl.GUID -and $UsageByGuid.ContainsKey($Tpl.GUID)) {
                foreach ($U in $UsageByGuid[$Tpl.GUID]) {
                    $Entry = $U | Select-Object *
                    $Entry | Add-Member -NotePropertyName 'matchType' -NotePropertyValue 'direct' -Force
                    $Usage.Add($Entry)
                }
            }
            if ($Tpl.package -and $UsageByPackage.ContainsKey($Tpl.package)) {
                foreach ($U in $UsageByPackage[$Tpl.package]) {
                    # Avoid duplicates when the same template matches both GUID and package
                    if (-not ($Usage | Where-Object { $_.templateId -eq $U.templateId })) {
                        $Entry = $U | Select-Object *
                        $Entry | Add-Member -NotePropertyName 'matchType' -NotePropertyValue 'package' -Force
                        $Entry | Add-Member -NotePropertyName 'package' -NotePropertyValue $Tpl.package -Force
                        $Usage.Add($Entry)
                    }
                }
            }
            $Tpl | Add-Member -NotePropertyName 'usage' -NotePropertyValue @($Usage) -Force
        }
    } else {
        if ($Request.query.mode -eq 'Tag') {
            #when the mode is tag, show all the potential tags, return the object with: label: tag, value: tag, count: number of templates with that tag, unique only
            $Templates = @($RawTemplates | Where-Object { $_.Package } | Group-Object -Property Package | ForEach-Object {
                    $package = $_.Name
                    $packageTemplates = @($_.Group)
                    $templateCount = $packageTemplates.Count
                    [pscustomobject]@{
                        label         = "$($package) ($templateCount Templates)"
                        value         = $package
                        type          = 'tag'
                        templateCount = $templateCount
                        templates     = @($packageTemplates | ForEach-Object {
                                try {
                                    $JSONData = $_.JSON | ConvertFrom-Json -Depth 100 -ErrorAction SilentlyContinue
                                    $data = $JSONData.RAWJson | ConvertFrom-Json -Depth 100 -ErrorAction SilentlyContinue
                                    $data | Add-Member -NotePropertyName 'displayName' -NotePropertyValue $JSONData.Displayname -Force
                                    $data | Add-Member -NotePropertyName 'description' -NotePropertyValue $JSONData.Description -Force
                                    $data | Add-Member -NotePropertyName 'Type' -NotePropertyValue $JSONData.Type -Force
                                    $data | Add-Member -NotePropertyName 'GUID' -NotePropertyValue $_.RowKey -Force
                                    $data | Add-Member -NotePropertyName 'package' -NotePropertyValue $_.Package -Force
                                    $data | Add-Member -NotePropertyName 'source' -NotePropertyValue $_.Source -Force
                                    $data | Add-Member -NotePropertyName 'isSynced' -NotePropertyValue (![string]::IsNullOrEmpty($_.SHA)) -Force
                                    $data | Add-Member -NotePropertyName 'reusableSettings' -NotePropertyValue $JSONData.ReusableSettings -Force
                                    $data
                                } catch {

                                }
                            })
                    }
                } | Sort-Object -Property label)
        } else {
            $Templates = $RawTemplates.JSON | ForEach-Object { try { ConvertFrom-Json -InputObject $_ -Depth 100 -ErrorAction SilentlyContinue } catch {} }

        }
    }

    if ($Request.query.ID) { $Templates = $Templates | Where-Object -Property guid -EQ $Request.query.id }

    # Sort all output regardless of view condition
    $Templates = $Templates | Sort-Object -Property displayName

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = ConvertTo-Json -Depth 100 -InputObject @($Templates)
        })

}
