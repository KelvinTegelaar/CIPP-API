function Invoke-ListIntuneTemplates {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Endpoint.MEM.Read
    .DESCRIPTION
        Lists the saved Intune policy templates. On first call the templates shipped with CIPP are imported into the templates table. These are CIPP templates, not a tenant's deployed policies.
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
            $Row = $_
            try {
                $JSONData = $Row.JSON | ConvertFrom-Json -Depth 100 -ErrorAction SilentlyContinue
                $data = $JSONData.RAWJson | ConvertFrom-Json -Depth 100 -ErrorAction SilentlyContinue
                if ($null -eq $data) { throw 'RAWJson is empty or not valid JSON' }
                $data | Add-Member -NotePropertyMembers ([ordered]@{
                        displayName      = $JSONData.Displayname
                        description      = $JSONData.Description
                        Type             = $JSONData.Type
                        GUID             = $Row.RowKey
                        package          = $Row.Package
                        isSynced         = (![string]::IsNullOrEmpty($Row.SHA))
                        source           = $Row.Source
                        reusableSettings = $JSONData.ReusableSettings
                    }) -Force
                $data
            } catch {
                # A row that fails to parse used to be dropped from this list entirely, so a corrupt
                # template stayed selectable in the deploy pickers (which use the raw list) while
                # being invisible here. Surface a stub so the broken row can be found and deleted.
                [PSCustomObject]@{
                    displayName = "$($JSONData.Displayname ?? $Row.RowKey) [corrupt template: $($_.Exception.Message)]"
                    description = 'This template row failed to parse and cannot be deployed. Delete it from the template list and recreate it.'
                    Type        = $JSONData.Type
                    GUID        = $Row.RowKey
                    package     = $Row.Package
                    isSynced    = (![string]::IsNullOrEmpty($Row.SHA))
                    source      = $Row.Source
                    corrupt     = $true
                }
            }

        } | Sort-Object -Property displayName

        # Build a lookup of what references each Intune template (by GUID or package): the
        # legacy standards templates and the baselines (#1220 - templates deployed only through
        # a baseline used to show as unused, which invites deleting the wrong one).
        $UsageByGuid = @{}
        $UsageByPackage = @{}
        $AddUsage = {
            param($Lookup, $Key, $Info)
            if (-not $Lookup.ContainsKey($Key)) { $Lookup[$Key] = [System.Collections.Generic.List[object]]::new() }
            $Lookup[$Key].Add($Info)
        }
        $StdTemplates = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'StandardsTemplateV2'"
        foreach ($StdRaw in $StdTemplates) {
            try {
                $StdData = $StdRaw.JSON | ConvertFrom-Json -Depth 100 -ErrorAction SilentlyContinue
                if (-not $StdData -or -not $StdData.standards) { continue }
                $IsDrift = $StdData.type -eq 'drift'
                $IntuneEntries = $StdData.standards.IntuneTemplate
                if (-not $IntuneEntries) { continue }
                $Items = if ($IntuneEntries -is [System.Collections.IEnumerable] -and $IntuneEntries -isnot [string]) { $IntuneEntries } else { @($IntuneEntries) }
                foreach ($Item in $Items) {
                    $Actions = @($Item.action | ForEach-Object { $_.value ?? $_ })
                    $StdInfo = [pscustomobject]@{
                        kind             = 'Standards Template'
                        templateName     = $StdData.templateName
                        templateId       = $StdRaw.RowKey
                        isDrift          = $IsDrift
                        stage            = $null
                        stageName        = $null
                        stageCount       = $null
                        remediateEnabled = [bool]($Actions -contains 'Remediate')
                        cippLink         = "/tenant/standards/templates/template?id=$($StdRaw.RowKey)$(if ($IsDrift) { '&type=drift' })"
                    }
                    if ($Item.TemplateList.value) { & $AddUsage $UsageByGuid "$($Item.TemplateList.value)" $StdInfo }
                    if ($Item.'TemplateList-Tags'.value) { & $AddUsage $UsageByPackage "$($Item.'TemplateList-Tags'.value)" $StdInfo }
                }
            } catch {}
        }

        # Baselines keep one delta row per standard instance per assignment scope. The
        # IntuneTemplate instance names the template GUID, IntuneTemplatePackage names the
        # package tag. Fold the scope rows together so a baseline is listed once per stage.
        try {
            $RolloutTable = Get-CippTable -tablename 'BaselineRollouts'
            $Rollouts = @{}
            foreach ($RolloutRow in @(Get-CIPPAzDataTableEntity @RolloutTable -Filter "PartitionKey eq 'rollout'")) {
                $StageNames = @()
                try { $StageNames = @(($RolloutRow.Stages | ConvertFrom-Json -ErrorAction Stop).name) } catch {}
                $Rollouts["$($RolloutRow.RowKey)"] = [pscustomobject]@{ name = $RolloutRow.templateName; stageNames = $StageNames }
            }
            $DeltaTable = Get-CippTable -tablename 'Baselines'
            # Prefix match: every instance key for both standards starts with 'IntuneTemplate'.
            $Deltas = @(Get-CIPPAzDataTableEntity @DeltaTable -Filter "PartitionKey eq 'standardItem' and standardName ge 'IntuneTemplate' and standardName lt 'IntuneTemplatf'")
            $BaselineUsage = @{}
            foreach ($Delta in $Deltas) {
                $BaseName = ("$($Delta.standardName)" -split '#')[0]
                if ($BaseName -notin @('IntuneTemplate', 'IntuneTemplatePackage')) { continue }
                $Rollout = $Rollouts["$($Delta.templateId)"]
                if (-not $Rollout) { continue }
                $Variables = $(try { $Delta.expectedValue | ConvertFrom-Json -Depth 100 } catch { $null })
                $RawValue = if ($BaseName -eq 'IntuneTemplate') { $Variables.intuneTemplate } else { $Variables.intuneTemplatePackage }
                # Stored as a bare id, an option object, or an array of either (older multi-selects).
                $Values = @($RawValue | ForEach-Object { "$($_.value ?? $_)" } | Where-Object { $_ })
                $Stage = [int]($Delta.stage ?? 1)
                foreach ($Value in $Values) {
                    $Key = "$($Delta.templateId)|$Stage|$BaseName|$Value"
                    if ($BaselineUsage.ContainsKey($Key)) {
                        # Any scope with remediation on counts as remediating.
                        if ([bool]$Delta.remediateEnabled) { $BaselineUsage[$Key].remediateEnabled = $true }
                        continue
                    }
                    $Info = [pscustomobject]@{
                        kind             = 'Baseline'
                        templateName     = $Rollout.name
                        templateId       = "$($Delta.templateId)"
                        isDrift          = $true
                        stage            = $Stage
                        stageName        = $Rollout.stageNames[$Stage - 1]
                        stageCount       = $Rollout.stageNames.Count
                        remediateEnabled = [bool]$Delta.remediateEnabled
                        cippLink         = "/tenant/baselines/template?id=$($Delta.templateId)"
                    }
                    $BaselineUsage[$Key] = $Info
                    if ($BaseName -eq 'IntuneTemplate') { & $AddUsage $UsageByGuid $Value $Info } else { & $AddUsage $UsageByPackage $Value $Info }
                }
            }
        } catch {
            Write-Information "ListIntuneTemplates: baseline usage lookup failed: $($_.Exception.Message)"
        }

        # One readable line per reference, shown as a chip in the Usage column.
        $UsageLabel = {
            param($Entry)
            $Parts = [System.Collections.Generic.List[string]]::new()
            $Parts.Add("$($Entry.templateName ?? $Entry.templateId)")
            if ($Entry.kind -eq 'Baseline') {
                $StageText = if ($Entry.stageName) { "Stage $($Entry.stage): $($Entry.stageName)" } else { "Stage $($Entry.stage)" }
                if ($Entry.stageCount -gt 1) { $StageText += " of $($Entry.stageCount)" }
                $Parts.Add($StageText)
            } else {
                $Parts.Add('Standards template')
            }
            $Parts.Add($(if ($Entry.remediateEnabled) { 'Remediate' } else { 'Report only' }))
            if ($Entry.matchType -eq 'package') { $Parts.Add("via package $($Entry.package)") }
            $Parts -join ' | '
        }

        # Attach usage list to each Intune template
        foreach ($Tpl in $Templates) {
            $Usage = [System.Collections.Generic.List[object]]::new()
            if ($Tpl.GUID -and $UsageByGuid.ContainsKey($Tpl.GUID)) {
                foreach ($U in $UsageByGuid[$Tpl.GUID]) {
                    $Entry = $U | Select-Object *
                    $Entry | Add-Member -NotePropertyName 'matchType' -NotePropertyValue 'direct' -Force
                    $Entry | Add-Member -NotePropertyName 'label' -NotePropertyValue (& $UsageLabel $Entry) -Force
                    $Usage.Add($Entry)
                }
            }
            if ($Tpl.package -and $UsageByPackage.ContainsKey($Tpl.package)) {
                foreach ($U in $UsageByPackage[$Tpl.package]) {
                    # Avoid duplicates when the same template (and, for a baseline, the same stage) matches both GUID and package
                    if (-not ($Usage | Where-Object { $_.templateId -eq $U.templateId -and $_.stage -eq $U.stage })) {
                        $Entry = $U | Select-Object *
                        $Entry | Add-Member -NotePropertyName 'matchType' -NotePropertyValue 'package' -Force
                        $Entry | Add-Member -NotePropertyName 'package' -NotePropertyValue $Tpl.package -Force
                        $Entry | Add-Member -NotePropertyName 'label' -NotePropertyValue (& $UsageLabel $Entry) -Force
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
                                    $data | Add-Member -NotePropertyMembers ([ordered]@{
                                            displayName      = $JSONData.Displayname
                                            description      = $JSONData.Description
                                            Type             = $JSONData.Type
                                            GUID             = $_.RowKey
                                            package          = $_.Package
                                            source           = $_.Source
                                            isSynced         = (![string]::IsNullOrEmpty($_.SHA))
                                            reusableSettings = $JSONData.ReusableSettings
                                        }) -Force
                                    $data
                                } catch {

                                }
                            })
                    }
                } | Sort-Object -Property label)
        } else {
            # Force GUID to the table RowKey (the authoritative key the standards engine
            # resolves against). The JSON-embedded GUID can drift out of sync with the
            # RowKey after a community-repo re-sync, so never surface it as the selectable value.
            $Templates = $RawTemplates | ForEach-Object {
                try {
                    $Parsed = ConvertFrom-Json -InputObject $_.JSON -Depth 100 -ErrorAction SilentlyContinue
                    if ($Parsed) { $Parsed | Add-Member -NotePropertyName 'GUID' -NotePropertyValue $_.RowKey -Force }
                    $Parsed
                } catch {}
            }

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
