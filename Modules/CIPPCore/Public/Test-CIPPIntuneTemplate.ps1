function Test-CIPPIntuneTemplate {
    <#
    .SYNOPSIS
        Checks an Intune template for the things that stop it deploying.
    .DESCRIPTION
        Replays the preconditions Set-CIPPIntunePolicy depends on, without calling Graph, so a template
        that cannot deploy is refused when it is stored, imported or edited rather than on a tenant.

        Error findings mean deployment cannot succeed and callers refuse the write. Warning findings never
        block: the shipped catalog lags Intune, so an unknown setting may simply be new.

        TenantFilter adds the checks that need a tenant: unresolved replacement variables, and Endpoint
        Security settings the tenant does not offer.
    .PARAMETER RawJSON
        The policy payload, as a JSON string or an already parsed object.
    .PARAMETER TemplateType
        The template's recorded Type. Inferred from the payload when empty.
    .PARAMETER DisplayName
        The template's Displayname, used to resolve the name the policy deploys under.
    .PARAMETER TenantFilter
        Tenant to run the tenant-aware checks against. Omit for static validation only.
    .PARAMETER IncludeCatalogChecks
        Also resolve Catalog settings against the shipped setting catalog (unknown settings and
        options, collection size bounds).
    .EXAMPLE
        $Result = Test-CIPPIntuneTemplate -RawJSON $Template.RAWJson -TemplateType $Template.Type -DisplayName $Template.Displayname
        if (-not $Result.IsValid) { throw ($Result.Errors -join ' ') }
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        $RawJSON,
        [string]$TemplateType,
        [string]$DisplayName,
        [string]$TenantFilter,
        [switch]$IncludeCatalogChecks
    )

    $Findings = [System.Collections.Generic.List[pscustomobject]]::new()
    function Add-Finding([string]$Severity, [string]$Code, [string]$Path, [string]$Message) {
        $Findings.Add([pscustomobject]@{ Severity = $Severity; Code = $Code; Path = $Path; Message = $Message })
    }
    function Get-Result($Type, $Name) {
        $Errors = @($Findings.Where({ $_.Severity -eq 'Error' }).ForEach('Message'))
        [pscustomobject]@{
            IsValid     = $Errors.Count -eq 0
            Type        = $Type
            DisplayName = $Name
            Findings    = @($Findings)
            Errors      = $Errors
            Warnings    = @($Findings.Where({ $_.Severity -eq 'Warning' }).ForEach('Message'))
        }
    }

    $Policy = $null
    if ($RawJSON -is [string]) {
        if (-not [string]::IsNullOrWhiteSpace($RawJSON)) {
            try {
                $Policy = $RawJSON | ConvertFrom-Json -Depth 100 -ErrorAction Stop
            } catch {
                Add-Finding 'Error' 'InvalidJson' '' "The policy payload is not valid JSON: $($_.Exception.Message)"
            }
        }
    } else {
        $Policy = $RawJSON
    }
    if (-not $Policy) {
        if ($Findings.Count -eq 0) { Add-Finding 'Error' 'EmptyPayload' '' 'The template has no policy payload.' }
        return Get-Result $null $DisplayName
    }

    $ResolvedType = Get-CIPPIntuneTemplateType -Type $TemplateType -RawJson $Policy
    $DeployableTypes = Get-CIPPIntuneDeployableType
    if (-not $ResolvedType) {
        Add-Finding 'Error' 'UnknownType' 'Type' 'The template type could not be determined from the stored type or the payload. Re-import or recapture the template.'
    } elseif ($ResolvedType -notin $DeployableTypes) {
        Add-Finding 'Error' 'UndeployableType' 'Type' "Template type '$ResolvedType' cannot be deployed. Deployment supports: $($DeployableTypes -join ', ')."
    } elseif (-not $TemplateType) {
        Add-Finding 'Warning' 'InferredType' 'Type' "The template has no stored type; '$ResolvedType' was inferred from the payload."
    }

    # Some types deploy under a name read from the payload rather than the Displayname column.
    $JsonText = $RawJSON -is [string] ? $RawJSON : (ConvertTo-Json -InputObject $Policy -Depth 100 -Compress)
    $ResolvedName = $ResolvedType ? (Get-CIPPIntunePolicyName -TemplateType $ResolvedType -RawJSON $JsonText -DisplayName $DisplayName) : $DisplayName
    if ([string]::IsNullOrWhiteSpace($ResolvedName)) {
        Add-Finding 'Error' 'NoDisplayName' 'displayName' 'The template resolves to no policy name, so the deployed policy would be unnamed.'
    }

    switch ($ResolvedType) {
        'AppProtection' {
            if (-not (Get-CIPPAppProtectionPolicyUrl -Policy $Policy)) {
                Add-Finding 'Error' 'AppProtectionPlatformUnknown' '@odata.type' 'This App Protection template identifies no platform, so the collection to deploy it to cannot be determined.'
            }
        }
        'deviceCompliancePolicies' {
            # Set-CIPPIntunePolicy assigns into this property directly and throws when it is absent.
            if ($Policy.PSObject.Properties.Name -notcontains 'scheduledActionsForRule') {
                Add-Finding 'Error' 'MissingScheduledActions' 'scheduledActionsForRule' 'A compliance policy must carry scheduledActionsForRule.'
            }
            if (-not $Policy.'@odata.type') {
                Add-Finding 'Warning' 'MissingODataType' '@odata.type' 'No @odata.type, so an existing policy cannot be matched by type and a duplicate may be created.'
            }
        }
        'Device' {
            if (-not $Policy.'@odata.type') {
                Add-Finding 'Error' 'MissingODataType' '@odata.type' 'A device configuration must carry @odata.type. Graph cannot determine the policy type without it.'
            }
        }
        'Admin' {
            if ($Policy.PSObject.Properties.Name -notcontains 'added') {
                Add-Finding 'Error' 'MissingDefinitionValues' 'added' 'An administrative template must carry an "added" array of definition values.'
            } elseif (@($Policy.added).Count -eq 0) {
                Add-Finding 'Warning' 'EmptyDefinitionValues' 'added' 'The "added" array is empty, so this template would create a policy with no configured settings.'
            }
        }
        'Catalog' {
            foreach ($Finding in (Test-CIPPIntuneCatalogPayload -Policy $Policy -IncludeCatalogChecks:$IncludeCatalogChecks)) {
                $Findings.Add($Finding)
            }
        }
    }

    if ($TenantFilter) {
        try {
            $Replaced = Get-CIPPTextReplacement -TenantFilter $TenantFilter -Text $JsonText -EscapeForJson
            # %name% is also Windows environment variable syntax, which is meant to reach the device unexpanded.
            $EnvironmentTokens = @(
                '%programfiles%', '%programfiles(x86)%', '%programdata%', '%windir%', '%systemroot%',
                '%systemdrive%', '%appdata%', '%localappdata%', '%temp%', '%tmp%', '%userprofile%',
                '%allusersprofile%', '%public%', '%computername%', '%username%', '%homedrive%',
                '%homepath%', '%path%', '%commonprogramfiles%', '%commonprogramfiles(x86)%'
            )
            $Unresolved = [System.Collections.Generic.SortedSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($Match in [regex]::Matches($Replaced, '%[A-Za-z0-9_.()-]+%')) {
                if ($Match.Value.ToLowerInvariant() -notin $EnvironmentTokens) { $null = $Unresolved.Add($Match.Value) }
            }
            if ($Unresolved.Count -gt 0) {
                Add-Finding 'Warning' 'UnresolvedVariable' '' "These replacement variables do not resolve for $TenantFilter and would deploy literally: $(@($Unresolved) -join ', ')."
            }
        } catch {
            Add-Finding 'Warning' 'ReplacementCheckFailed' '' "The replacement variables could not be checked for $TenantFilter : $($_.Exception.Message)"
        }

        if ($ResolvedType -eq 'Catalog' -and $Policy.templateReference.templateId) {
            try {
                $Before = @($Policy.settings).Count
                $Filtered = Select-CIPPIntuneAvailableSetting -Policy ($JsonText | ConvertFrom-Json -Depth 100) -TenantFilter $TenantFilter
                $After = @($Filtered.settings).Count
                if ($After -eq 0 -and $Before -gt 0) {
                    Add-Finding 'Error' 'NoSettingsAvailable' 'settings' "None of this template's $Before settings are offered by $TenantFilter, so deployment would create an empty policy."
                } elseif ($After -lt $Before) {
                    Add-Finding 'Warning' 'SettingsUnavailable' 'settings' "$($Before - $After) of $Before settings are not offered by $TenantFilter and would be dropped on deployment."
                }
            } catch {
                Add-Finding 'Warning' 'AvailabilityCheckFailed' 'settings' "Setting availability could not be checked against $TenantFilter : $($_.Exception.Message)"
            }
        }
    }

    return Get-Result $ResolvedType $ResolvedName
}
