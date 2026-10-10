function Get-CIPPIntuneAdminTemplateDefinitionValue {
    <#
    .SYNOPSIS
        Reads an administrative template policy's settings as an updateDefinitionValues payload.
    .DESCRIPTION
        Builds the {added, updated, deletedIds} payload that deploys a groupPolicyConfiguration's
        settings: one entry per definition value with its groupPolicyDefinitions('<id>') bind, enabled
        state and presentation values. This is the shape stored in an Admin template's RAWJson and the
        shape Get-CIPPIntunePolicy compares a live policy against.

        With -IncludeIdentity each entry also carries the setting's identity next to its bind
        (definition: displayName, categoryPath, classType, policyType; presentation: label, type and
        position within the definition). Definitions from an imported ADMX file are minted with a new id
        in every tenant, so this is what lets Resolve-CIPPIntuneAdminTemplateBinding find the same
        setting in another tenant at deployment. Graph does not accept these properties on a definition
        value, so the resolver removes them before posting.
    .PARAMETER PolicyId
        The groupPolicyConfiguration id.
    .PARAMETER TenantFilter
        The tenant the policy lives in.
    .PARAMETER IncludeIdentity
        Record each setting's identity next to its bind, for a template that will be deployed elsewhere.
    .PARAMETER DefinitionValues
        The policy's definition values when the caller has already read them (with $expand=definition),
        so they are not read twice.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PolicyId,
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [switch]$IncludeIdentity,
        $DefinitionValues
    )

    $PolicyUri = "https://graph.microsoft.com/beta/deviceManagement/groupPolicyConfigurations('$PolicyId')"
    if (-not $PSBoundParameters.ContainsKey('DefinitionValues')) {
        # Without the expand the value carries no definition at all, and the bind would be built on
        # an empty id.
        $DefinitionValues = New-GraphGetRequest -uri "$PolicyUri/definitionValues?`$expand=definition" -tenantid $TenantFilter
    }
    $DefinitionValues = @($DefinitionValues | Where-Object { $_.id })

    $Identities = @{}
    $Presentations = @{}
    if ($IncludeIdentity -and $DefinitionValues.Count -gt 0) {
        # The expanded definition does not reliably carry categoryPath; read each definition and its
        # presentation list (in ADMX order) in one batch.
        $Requests = [System.Collections.Generic.List[object]]::new()
        foreach ($DefinitionId in @($DefinitionValues.definition.id | Where-Object { $_ } | Select-Object -Unique)) {
            $Requests.Add([PSCustomObject]@{ id = "definition-$DefinitionId"; method = 'GET'; url = "/deviceManagement/groupPolicyDefinitions('$DefinitionId')?`$select=id,displayName,categoryPath,classType,policyType" })
            $Requests.Add([PSCustomObject]@{ id = "presentations-$DefinitionId"; method = 'GET'; url = "/deviceManagement/groupPolicyDefinitions('$DefinitionId')/presentations" })
        }
        foreach ($Reply in @(New-GraphBulkRequest -Requests @($Requests) -tenantid $TenantFilter)) {
            if ($Reply.status -ne 200 -or -not $Reply.id) { continue }
            if ($Reply.id -like 'definition-*') {
                $Identities[$Reply.id.Substring(11)] = $Reply.body
            } elseif ($Reply.id -like 'presentations-*') {
                $Body = if ($null -ne $Reply.body.value) { $Reply.body.value } else { $Reply.body }
                $Presentations[$Reply.id.Substring(14)] = @($Body | Where-Object { $_.id })
            }
        }
    }

    $Added = foreach ($DefinitionValue in $DefinitionValues) {
        $DefinitionId = [string]$DefinitionValue.definition.id
        $DefinitionUri = "https://graph.microsoft.com/beta/deviceManagement/groupPolicyDefinitions('$DefinitionId')"
        $PresentationValues = New-GraphGetRequest -uri "$PolicyUri/definitionValues('$($DefinitionValue.id)')/presentationValues?`$expand=presentation" -tenantid $TenantFilter | ForEach-Object {
            $Value = $_
            if (-not $Value.id) { return }
            $Entry = [ordered]@{
                id                        = $Value.id
                'presentation@odata.bind' = "$DefinitionUri/presentations('$($Value.presentation.id)')"
            }
            if ($Value.values) { $Entry['values'] = $Value.values }
            if ($null -ne $Value.value) { $Entry['value'] = $Value.value }
            if ($Value.'@odata.type') { $Entry['@odata.type'] = $Value.'@odata.type' }
            if ($IncludeIdentity) {
                $List = if ($Presentations.ContainsKey($DefinitionId)) { $Presentations[$DefinitionId] } else { @() }
                $Position = [array]::FindIndex([object[]]$List, [Predicate[object]] { param($P) [string]$P.id -eq [string]$Value.presentation.id })
                $Entry['presentation'] = [ordered]@{
                    id            = $Value.presentation.id
                    label         = [string]$Value.presentation.label
                    '@odata.type' = [string]$Value.presentation.'@odata.type'
                    index         = if ($Position -ge 0) { $Position } else { $null }
                }
            }
            [pscustomobject]$Entry
        }
        $Item = [ordered]@{
            'definition@odata.bind' = $DefinitionUri
            enabled                 = $DefinitionValue.enabled
            presentationValues      = @($PresentationValues)
        }
        if ($IncludeIdentity) {
            $Detail = if ($Identities.ContainsKey($DefinitionId)) { $Identities[$DefinitionId] } else { $DefinitionValue.definition }
            $Item['definition'] = [ordered]@{
                id           = $DefinitionId
                displayName  = [string]$Detail.displayName
                categoryPath = [string]$Detail.categoryPath
                classType    = [string]$Detail.classType
                policyType   = [string]$Detail.policyType
            }
        }
        [pscustomobject]$Item
    }

    return [pscustomobject]@{
        added      = @($Added)
        updated    = @()
        deletedIds = @()
    }
}
