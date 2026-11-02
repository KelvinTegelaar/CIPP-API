function Resolve-CIPPIntuneAdminTemplateBinding {
    <#
    .SYNOPSIS
        Rewrites an administrative template's definition binds to the ids of the tenant it is deployed to.
    .DESCRIPTION
        An administrative template (deviceManagement/groupPolicyConfigurations) stores each setting as a
        groupPolicyDefinitions('<id>') bind plus presentations('<id>') binds for its values. Built-in
        definitions have one id in every tenant, but a definition from an imported ADMX file is minted
        with a new id in every tenant, and again on every re-import. A template captured in one tenant
        therefore binds to ids that do not exist in the next, and Graph rejects updateDefinitionValues
        with a generic error.

        Get-CIPPIntuneAdminTemplateDefinitionValue records each setting's identity next to its bind
        (definition: displayName, categoryPath, classType; presentation: label, type, position). This
        function checks which bound ids exist in the target tenant and, for those that do not, finds the
        same setting there by that identity and rewrites the binds. The identity metadata is removed from
        the result, because Graph does not accept it on a definition value.

        A setting whose ADMX has not been imported into the target tenant is reported by name with what
        to do about it. A template captured before the identity was recorded carries only ids, which are
        kept when the tenant has them (the same tenant, or a re-deploy) and rejected with an explanation
        otherwise.
    .PARAMETER RawJSON
        The template payload: {added, updated, deletedIds} as stored in the template's RAWJson, after
        text replacement.
    .PARAMETER TenantFilter
        The tenant the policy is being deployed to.
    .PARAMETER DisplayName
        The policy name, used in messages only.
    .OUTPUTS
        The payload as a JSON string, ready to post to updateDefinitionValues.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RawJSON,
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [string]$DisplayName,
        $Headers,
        $APIName = 'Resolve-CIPPIntuneAdminTemplateBinding'
    )

    $BindPattern = "groupPolicyDefinitions\('([0-9a-fA-F-]{36})'\)"
    $Policy = $RawJSON | ConvertFrom-Json -Depth 100
    $Added = @($Policy.added | Where-Object { $_ })
    $PolicyLabel = if ($DisplayName) { "'$DisplayName'" } else { 'template' }

    $Strip = {
        foreach ($Item in $Added) {
            if ($Item.PSObject.Properties['definition']) { $Item.PSObject.Properties.Remove('definition') }
            foreach ($PresentationValue in @($Item.presentationValues | Where-Object { $_ })) {
                if ($PresentationValue.PSObject.Properties['presentation']) { $PresentationValue.PSObject.Properties.Remove('presentation') }
            }
        }
    }

    if ($Added.Count -eq 0) {
        & $Strip
        return (ConvertTo-Json -InputObject $Policy -Depth 100 -Compress)
    }

    # Which of the bound definitions does this tenant have? One batch, one GET per distinct id.
    $BoundIds = [System.Collections.Generic.List[string]]::new()
    foreach ($Item in $Added) {
        $Match = [regex]::Match([string]$Item.'definition@odata.bind', $BindPattern)
        if ($Match.Success) {
            $Id = $Match.Groups[1].Value.ToLowerInvariant()
            if (-not $BoundIds.Contains($Id)) { $BoundIds.Add($Id) }
        }
    }
    $ExistenceRequests = [System.Collections.Generic.List[object]]::new()
    foreach ($Id in $BoundIds) {
        $ExistenceRequests.Add([PSCustomObject]@{
                id     = $Id
                method = 'GET'
                url    = "/deviceManagement/groupPolicyDefinitions('$Id')?`$select=id"
            })
    }
    $Present = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    if ($ExistenceRequests.Count -gt 0) {
        foreach ($Reply in @(New-GraphBulkRequest -Requests @($ExistenceRequests) -tenantid $TenantFilter)) {
            if ($Reply.status -eq 200 -and $Reply.body.id) { [void]$Present.Add([string]$Reply.body.id) }
        }
    }

    $DefinitionCache = @{}
    $PresentationCache = @{}
    $NotImported = [System.Collections.Generic.List[string]]::new()
    $NoIdentity = [System.Collections.Generic.List[string]]::new()

    # The tenant's definitions in one category and class, fetched once per category.
    $GetCandidates = {
        param($Identity)
        $Class = [string]$Identity.classType
        $Category = [string]$Identity.categoryPath
        $Filter = if ($Category) {
            "classType eq '$(ConvertTo-CIPPODataFilterValue -Value $Class -Type String)' and categoryPath eq '$(ConvertTo-CIPPODataFilterValue -Value $Category -Type String)'"
        } else {
            "classType eq '$(ConvertTo-CIPPODataFilterValue -Value $Class -Type String)' and displayName eq '$(ConvertTo-CIPPODataFilterValue -Value ([string]$Identity.displayName) -Type String)'"
        }
        if (-not $DefinitionCache.ContainsKey($Filter)) {
            $DefinitionCache[$Filter] = @(New-GraphGetRequest -uri "https://graph.microsoft.com/beta/deviceManagement/groupPolicyDefinitions?`$filter=$Filter&`$select=id,displayName,categoryPath,classType" -tenantid $TenantFilter | Where-Object { $_.id })
        }
        $DefinitionCache[$Filter]
    }

    foreach ($Item in $Added) {
        $Match = [regex]::Match([string]$Item.'definition@odata.bind', $BindPattern)
        if (-not $Match.Success) { continue }
        $SourceId = $Match.Groups[1].Value
        if ($Present.Contains($SourceId)) { continue }

        $Identity = $Item.definition
        if (-not $Identity -or [string]::IsNullOrWhiteSpace([string]$Identity.displayName)) {
            $NoIdentity.Add($SourceId)
            continue
        }

        $Candidates = @(& $GetCandidates $Identity | Where-Object { [string]$_.displayName -eq [string]$Identity.displayName })
        if ($Identity.categoryPath -and $Candidates.Count -gt 1) {
            $Exact = @($Candidates | Where-Object { [string]$_.categoryPath -eq [string]$Identity.categoryPath })
            if ($Exact.Count -gt 0) { $Candidates = $Exact }
        }
        if ($Candidates.Count -eq 0) {
            $NotImported.Add("'$($Identity.displayName)' ($($Identity.categoryPath), $($Identity.classType))")
            continue
        }
        if ($Candidates.Count -gt 1) {
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Administrative template $PolicyLabel : $($Candidates.Count) definitions in $TenantFilter match '$($Identity.displayName)' ($($Identity.categoryPath), $($Identity.classType)); using the first." -Sev Warning
        }
        $Target = $Candidates[0]
        $Item.'definition@odata.bind' = "https://graph.microsoft.com/beta/deviceManagement/groupPolicyDefinitions('$($Target.id)')"

        $PresentationValues = @($Item.presentationValues | Where-Object { $_ })
        if ($PresentationValues.Count -eq 0) { continue }
        if (-not $PresentationCache.ContainsKey([string]$Target.id)) {
            $PresentationCache[[string]$Target.id] = @(New-GraphGetRequest -uri "https://graph.microsoft.com/beta/deviceManagement/groupPolicyDefinitions('$($Target.id)')/presentations" -tenantid $TenantFilter | Where-Object { $_.id })
        }
        $TargetPresentations = $PresentationCache[[string]$Target.id]

        for ($Index = 0; $Index -lt $PresentationValues.Count; $Index++) {
            $PresentationValue = $PresentationValues[$Index]
            $PresentationIdentity = $PresentationValue.presentation
            $Type = [string]$PresentationIdentity.'@odata.type'
            $SameType = @($TargetPresentations | Where-Object { -not $Type -or [string]$_.'@odata.type' -eq $Type })

            # The label names the field when the ADMX gave it one; otherwise the position in the
            # definition's presentation list (its order in the ADMX) is what identifies it, checked
            # against the type so a re-ordered ADMX cannot bind a list value to a text box.
            $Chosen = $null
            $Label = [string]$PresentationIdentity.label
            if ($Label) {
                $Chosen = $SameType | Where-Object { [string]$_.label -eq $Label } | Select-Object -First 1
            }
            if (-not $Chosen -and $null -ne $PresentationIdentity.index) {
                $Position = [int]$PresentationIdentity.index
                if ($Position -ge 0 -and $Position -lt $TargetPresentations.Count -and $TargetPresentations[$Position] -in $SameType) {
                    $Chosen = $TargetPresentations[$Position]
                }
            }
            if (-not $Chosen -and -not $PresentationIdentity -and $PresentationValues.Count -eq $TargetPresentations.Count) {
                # Captured before the presentation identity was recorded: the values were stored in
                # the order the presentations came back, which is the ADMX order on both sides.
                $Chosen = $TargetPresentations[$Index]
            }
            if (-not $Chosen -and $SameType.Count -eq 1) {
                $Chosen = $SameType[0]
            }
            if (-not $Chosen) {
                $NotImported.Add("value $($Index + 1) of '$($Identity.displayName)' ($($Identity.categoryPath), $($Identity.classType)) has no matching field in this tenant's copy of the setting")
                continue
            }
            $PresentationValue.'presentation@odata.bind' = "https://graph.microsoft.com/beta/deviceManagement/groupPolicyDefinitions('$($Target.id)')/presentations('$($Chosen.id)')"
        }
    }

    if ($NoIdentity.Count -gt 0) {
        $Message = "Administrative template $PolicyLabel references definition ids that do not exist in $TenantFilter ($($NoIdentity -join ', ')). Settings from an imported ADMX file have a different id in every tenant, and this template was captured before CIPP recorded which settings those ids belong to, so they cannot be matched in this tenant. Re-create the template from the source tenant and deploy it again."
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Message -Sev Error
        throw $Message
    }
    if ($NotImported.Count -gt 0) {
        $Message = "Administrative template $PolicyLabel uses settings that are not available in $TenantFilter : $($NotImported -join '; '). These settings come from an imported ADMX file. Import the same ADMX and ADML files into $TenantFilter (Intune admin center > Devices > Configuration > Import ADMX), wait until the file shows as Available, then deploy again."
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Message -Sev Error
        throw $Message
    }

    & $Strip
    return (ConvertTo-Json -InputObject $Policy -Depth 100 -Compress)
}
