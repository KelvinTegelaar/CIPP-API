function Set-CIPPSensitivityLabel {
    <#
    .SYNOPSIS
        Deploy or update a single sensitivity label (+ optional label policy) in a tenant from a template object.
    .DESCRIPTION
        Single source of truth for sensitivity label deployment, shared by the HTTP deploy endpoint and
        the standard.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $TenantFilter,
        [Parameter(Mandatory)] $Template,
        [Parameter(Mandatory)] [string] $APIName,
        $Headers
    )

    # Valid New-Label/Set-Label parameter names (single source of truth, shared with the template endpoint).
    $LabelAllowedFields = Get-CIPPSensitivityLabelField
    $PolicyAllowedFields = @(
        'Name', 'Comment', 'Labels', 'AdvancedSettings', 'Settings',
        'ExchangeLocation', 'ExchangeLocationException',
        'SharePointLocation', 'SharePointLocationException',
        'OneDriveLocation', 'OneDriveLocationException',
        'ModernGroupLocation', 'ModernGroupLocationException',
        'PolicyTemplateInfo'
    )
    $PolicyLocationFields = $PolicyAllowedFields | Where-Object { $_ -like '*Location*' }
    $LabelPolicyAddPrefixed = @('Labels') + $PolicyLocationFields

    # Normalize the read shape (Get-Label LabelActions) into the flat New-/Set-Label parameter shape.
    # Flat manual JSON authored against the deploy schema passes through unchanged.
    $NormalizedLabel = ConvertTo-CIPPSensitivityLabelParams -Label $Template
    $LabelParams = Format-CIPPCompliancePolicyParams -Source $NormalizedLabel -AllowedFields $LabelAllowedFields
    $PolicySource = $Template.PolicyParams
    $LabelName = $LabelParams.Name

    # PswsHashtable parameters need the Exchange.GenericHashTable odata type to bind over the AdminApi.
    if ($LabelParams.ContainsKey('AdvancedSettings')) {
        $LabelParams['AdvancedSettings'] = ConvertTo-CIPPExoHashtable -InputObject $LabelParams['AdvancedSettings']
    }

    # Priority is valid on Set-Label but not New-Label, so it is applied via a dedicated Set-Label call below.
    $LabelPriority = $null
    if ($LabelParams.ContainsKey('Priority')) {
        $LabelPriority = $LabelParams['Priority']
        $LabelParams.Remove('Priority')
    }

    try {
        # A custom label color travels as the 'color' advanced setting. Validate the hex format up front
        # so a bad value fails with a clear message instead of an opaque compliance-endpoint error.
        # An empty string is valid: it clears a previously set color.
        if ($LabelParams.ContainsKey('AdvancedSettings')) {
            $ColorValue = $LabelParams['AdvancedSettings']['color']
            if (-not [string]::IsNullOrEmpty("$ColorValue") -and "$ColorValue" -notmatch '^#[0-9A-Fa-f]{6}$') {
                throw "Invalid label color '$ColorValue' in the AdvancedSettings of '$LabelName'. Use a 6-digit hex color like #40E0D0."
            }
        }

        # Template-based encryption is rebuilt in the target tenant from its rights definitions, because the
        # RMS template it was captured against is tenant-scoped and is deliberately dropped when the template
        # is normalized. Without rights definitions Purview has nothing to mint a template from, so fail with
        # something actionable rather than letting the compliance endpoint reject a half-configured label.
        # An explicit template id means the author is targeting a template that already exists here, so the
        # rights definitions are Purview's problem rather than ours.
        if ("$($LabelParams['EncryptionProtectionType'])" -eq 'Template' -and
            $LabelParams['EncryptionEnabled'] -ne $false -and
            -not $LabelParams['EncryptionTemplateId']) {
            $RightsCount = @($LabelParams['EncryptionRightsDefinitions'] | Where-Object { $_ }).Count
            if ($RightsCount -eq 0) {
                throw "Sensitivity label '$LabelName' uses template-based encryption but carries no rights definitions, so its protection cannot be rebuilt in another tenant. Re-create the template from the source label, or add EncryptionRightsDefinitions (e.g. 'AuthenticatedUsers:VIEW,DOCEDIT') to it."
            }
        }

        $ExistingLabels = try { New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-Label' -Compliance | Select-Object Name, DisplayName, Guid, ImmutableId } catch { @() }
        $ExistingLabelPolicies = try { New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-LabelPolicy' -Compliance | Select-Object Name } catch { @() }

        $LabelExists = [bool]($ExistingLabels | Where-Object { $_.Name -eq $LabelName -or $_.DisplayName -eq $LabelName })

        # ParentId identifies the parent of a sublabel by GUID, which is tenant-scoped in exactly the way an
        # RMS template id is: the source tenant's value addresses nothing here. Re-resolve it against this
        # tenant's labels, and if the parent has not been deployed yet create the label at the top level so
        # one missing parent does not fail the whole deploy. Only the create path needs this - an existing
        # label keeps whatever parent it already has.
        if (-not $LabelExists -and $LabelParams.ContainsKey('ParentId')) {
            $ParentId = "$($LabelParams['ParentId'])"
            $ParentInTenant = $ExistingLabels | Where-Object { "$($_.Guid)" -eq $ParentId -or "$($_.ImmutableId)" -eq $ParentId }

            if (-not $ParentInTenant) {
                # Only usable when the capture recorded a parent name alongside the GUID; Get-Label does not
                # always supply one, hence the fallback below.
                $ParentName = "$($NormalizedLabel.ParentLabelDisplayName ?? $NormalizedLabel.ParentLabelName)".Trim()
                $ParentByName = if ($ParentName) {
                    $ExistingLabels | Where-Object { $_.Name -eq $ParentName -or $_.DisplayName -eq $ParentName } | Select-Object -First 1
                }

                if ($ParentByName) {
                    $LabelParams['ParentId'] = $ParentByName.Guid ?? $ParentByName.ImmutableId
                } else {
                    $LabelParams.Remove('ParentId')
                    Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "The parent label for '$LabelName' does not exist in $TenantFilter, so it was deployed as a top-level label. Deploy the parent label first to keep the hierarchy." -sev Warning
                }
            }
        }

        if ($LabelExists) {
            # ParentId is a New-Label parameter only - an existing label cannot be reparented in place.
            $UpdateParams = @{}
            foreach ($Key in $LabelParams.Keys) {
                if ($Key -eq 'ParentId') { continue }
                $UpdateParams[$Key] = $LabelParams[$Key]
            }
            $SetParams = ConvertTo-CIPPComplianceSetParams -Params $UpdateParams -Identity $LabelName
            $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-Label' -cmdParams $SetParams -Compliance -useSystemMailbox $true
            $LabelAction = "Updated sensitivity label '$LabelName' in $TenantFilter."
        } else {
            $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'New-Label' -cmdParams $LabelParams -Compliance -useSystemMailbox $true
            $LabelAction = "Created sensitivity label '$LabelName' in $TenantFilter."
        }

        # Priority is Set-Label only (not a New-Label parameter) and is tenant-relative: a value valid in the
        # source tenant can be out of range in the target. Apply it best-effort so an invalid priority never
        # masks an otherwise successful label deployment.
        if ($null -ne $LabelPriority) {
            try {
                $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-Label' -cmdParams @{ Identity = $LabelName; Priority = $LabelPriority } -Compliance -useSystemMailbox $true
            } catch {
                Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Deployed sensitivity label '$LabelName' but could not set priority $LabelPriority in $($TenantFilter): $($_.Exception.Message)" -sev Warning
            }
        }

        if ($PolicySource) {
            $PolicyHash = Format-CIPPCompliancePolicyParams -Source $PolicySource -AllowedFields $PolicyAllowedFields
            # Settings/AdvancedSettings are PswsHashtable on New-/Set-LabelPolicy; template JSON authors
            # Settings as [key, value] pairs, which the helper also normalizes.
            foreach ($HashtableParam in @('AdvancedSettings', 'Settings')) {
                if ($PolicyHash.ContainsKey($HashtableParam)) {
                    $PolicyHash[$HashtableParam] = ConvertTo-CIPPExoHashtable -InputObject $PolicyHash[$HashtableParam]
                }
            }
            if (-not $PolicyHash.ContainsKey('Labels') -or -not $PolicyHash['Labels']) {
                $PolicyHash['Labels'] = @($LabelName)
            }
            $PolicyName = if ($PolicyHash.ContainsKey('Name') -and -not [string]::IsNullOrWhiteSpace([string]$PolicyHash['Name'])) {
                $PolicyHash['Name']
            } else {
                "$LabelName Policy"
            }
            $PolicyHash['Name'] = $PolicyName

            $LabelPolicyExists = [bool]($ExistingLabelPolicies | Where-Object { $_.Name -eq $PolicyName })

            if ($LabelPolicyExists) {
                $SetPolicyHash = ConvertTo-CIPPComplianceSetParams -Params $PolicyHash -Identity $PolicyName -AddPrefixFields $LabelPolicyAddPrefixed
                $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-LabelPolicy' -cmdParams $SetPolicyHash -Compliance -useSystemMailbox $true
            } else {
                $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'New-LabelPolicy' -cmdParams $PolicyHash -Compliance -useSystemMailbox $true
            }
        }

        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $LabelAction -sev Info
        return $LabelAction
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $msg = "Could not deploy sensitivity label '$LabelName' to $($TenantFilter): $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $msg -sev Error -LogData $ErrorMessage
        return $msg
    }
}
