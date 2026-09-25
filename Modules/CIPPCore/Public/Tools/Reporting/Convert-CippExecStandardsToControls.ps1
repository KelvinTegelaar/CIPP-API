function Convert-CippExecStandardsToControls {
    <#
    .SYNOPSIS
        Resolve the standards-comparison result into the Executive report's SecurityControls rows.
    .DESCRIPTION
        Server port of processStandardsData() from ExecutiveReportButton.jsx. Walks the first tenant's
        standards.* entries in a ListStandardsCompare result, decides Compliant vs Review the same way the
        client does (CurrentValue/ExpectedValue deep-equal with top-level keys sorted, else Value -eq $true),
        and resolves each standard's display name / description / tags from the standards catalog
        (Config\standards.json). Standards with no catalog entry fall back to a template display-name lookup
        or a formatted key, exactly as the client does. Pure transform - no data gathering - so it is
        unit-testable with sample data.
    .PARAMETER Compare
        The ListStandardsCompare Body: an array whose first element is the tenant's standards object.
    .PARAMETER Templates
        The listStandardTemplates Body, used only to resolve Intune/CA template GUIDs to display names.
    .PARAMETER Catalog
        The parsed Config\standards.json catalog (array of standard definitions).
    #>
    [CmdletBinding()]
    param(
        $Compare,
        $Templates = @(),
        $Catalog = @()
    )

    # JS parity: JSON.stringify of an object whose top-level keys are sorted. Nested objects keep their
    # order, which ConvertTo-Json also does, so structurally-equal values serialize identically on both
    # sides of the comparison.
    function ConvertTo-CanonicalJson($Value) {
        if ($null -eq $Value) { return 'null' }
        if ($Value -is [hashtable] -or $Value -is [System.Collections.Specialized.OrderedDictionary]) {
            $o = [ordered]@{}
            foreach ($k in ($Value.Keys | Sort-Object)) { $o[$k] = $Value[$k] }
            return ($o | ConvertTo-Json -Depth 20 -Compress)
        }
        if ($Value -is [System.Management.Automation.PSCustomObject]) {
            $o = [ordered]@{}
            foreach ($n in ($Value.PSObject.Properties.Name | Sort-Object)) { $o[$n] = $Value.$n }
            return ($o | ConvertTo-Json -Depth 20 -Compress)
        }
        return ($Value | ConvertTo-Json -Depth 20 -Compress)
    }

    $CompareArr = @($Compare)
    if ($CompareArr.Count -eq 0 -or $null -eq $CompareArr[0]) { return @() }
    $TenantData = $CompareArr[0]

    # Template GUID -> display name (Intune + Conditional Access templates, incl. Tags expansion).
    $TemplateMap = @{}
    foreach ($Template in @($Templates)) {
        $Std = $Template.standards
        if (-not $Std) { continue }
        foreach ($ListName in @('IntuneTemplate', 'ConditionalAccessTemplate')) {
            $Items = $Std.$ListName
            if (-not $Items) { continue }
            foreach ($Item in @($Items)) {
                $Tl = $Item.TemplateList
                if ($Tl -and $Tl.value -and $Tl.label) { $TemplateMap[([string]$Tl.value).ToLower()] = [string]$Tl.label }
                $Tags = $Item.'TemplateList-Tags'
                $TagTemplates = $null
                if ($Tags) {
                    $TagTemplates = $Tags.addedFields.templates
                    if (-not $TagTemplates) { $TagTemplates = $Tags.rawData.templates }
                }
                foreach ($Et in @($TagTemplates)) {
                    if ($Et.GUID -and ($Et.displayName -or $Et.name)) {
                        $TemplateMap[([string]$Et.GUID).ToLower()] = [string]($Et.displayName ?? $Et.name)
                    }
                }
            }
        }
    }

    # Catalog by full standard name (e.g. 'standards.CopilotSettings').
    $CatalogMap = @{}
    foreach ($C in @($Catalog)) { if ($C.name) { $CatalogMap[[string]$C.name] = $C } }

    $PropNames = if ($TenantData -is [hashtable]) { @($TenantData.Keys) } else { @($TenantData.PSObject.Properties.Name) }
    $Out = [System.Collections.Generic.List[object]]::new()

    foreach ($Key in $PropNames) {
        $KeyStr = [string]$Key
        if (-not $KeyStr.StartsWith('standards.') -or $KeyStr -eq 'tenantFilter') { continue }
        $Val = if ($TenantData -is [hashtable]) { $TenantData[$Key] } else { $TenantData.$Key }

        # Compliance: CurrentValue/ExpectedValue deep-equal (defined -> compared, null counts as defined),
        # else Value -eq $true.
        $HasCV = $false; $HasEV = $false; $CV = $null; $EV = $null; $ValueTrue = $false
        if ($Val -is [hashtable]) {
            $HasCV = $Val.ContainsKey('CurrentValue'); if ($HasCV) { $CV = $Val['CurrentValue'] }
            $HasEV = $Val.ContainsKey('ExpectedValue'); if ($HasEV) { $EV = $Val['ExpectedValue'] }
            if ($Val.ContainsKey('Value')) { $ValueTrue = ($Val['Value'] -eq $true) }
        } elseif ($Val -is [System.Management.Automation.PSCustomObject]) {
            $Props = $Val.PSObject.Properties.Name
            $HasCV = $Props -contains 'CurrentValue'; if ($HasCV) { $CV = $Val.CurrentValue }
            $HasEV = $Props -contains 'ExpectedValue'; if ($HasEV) { $EV = $Val.ExpectedValue }
            if ($Props -contains 'Value') { $ValueTrue = ($Val.Value -eq $true) }
        }

        $IsCompliant = $false
        if ($HasCV -and $HasEV) {
            $IsCompliant = ((ConvertTo-CanonicalJson $CV) -eq (ConvertTo-CanonicalJson $EV))
        } elseif ($ValueTrue) {
            $IsCompliant = $true
        }
        $Status = if ($IsCompliant) { 'Compliant' } else { 'Review' }

        $Def = $CatalogMap[$KeyStr]
        if ($Def) {
            $Tags = if ($Def.tag -and @($Def.tag).Count -gt 0) { (@($Def.tag) | Select-Object -First 2) -join ', ' } else { 'No tags' }
            $Name = [string]$Def.label
            $Desc = if (-not [string]::IsNullOrWhiteSpace([string]$Def.executiveText)) { [string]$Def.executiveText }
            elseif (-not [string]::IsNullOrWhiteSpace([string]$Def.helpText)) { [string]$Def.helpText }
            else { 'No description available' }
        } else {
            $Tags = 'No tags'
            $Desc = 'Security standard implementation'
            if ($KeyStr -match '^standards\.IntuneTemplate\.([0-9a-fA-F-]+)') {
                $Guid = $Matches[1]
                $Name = $TemplateMap[$Guid.ToLower()] ?? ('Intune Template - ' + $Guid.Substring(0, [Math]::Min(8, $Guid.Length)))
            } elseif ($KeyStr -match '^standards\.ConditionalAccessTemplate\.([0-9a-fA-F-]+)') {
                $Guid = $Matches[1]
                $Name = $TemplateMap[$Guid.ToLower()] ?? ('CA Template - ' + $Guid.Substring(0, [Math]::Min(8, $Guid.Length)))
            } else {
                $N = $KeyStr -replace '^standards\.', ''
                $N = ([regex]::Replace($N, '([A-Z])', ' $1')).Trim()
                $Name = if ($N.Length -gt 0) { $N.Substring(0, 1).ToUpper() + $N.Substring(1) } else { $N }
            }
        }

        $Out.Add(@{ name = $Name; description = $Desc; status = $Status; tags = $Tags })
    }

    return @($Out)
}
