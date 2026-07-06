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

    # Priority is valid on Set-Label but not New-Label, so it is applied via a dedicated Set-Label call below.
    $LabelPriority = $null
    if ($LabelParams.ContainsKey('Priority')) {
        $LabelPriority = $LabelParams['Priority']
        $LabelParams.Remove('Priority')
    }

    try {
        $ExistingLabels = try { New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-Label' -Compliance | Select-Object Name, DisplayName } catch { @() }
        $ExistingLabelPolicies = try { New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-LabelPolicy' -Compliance | Select-Object Name } catch { @() }

        $LabelExists = [bool]($ExistingLabels | Where-Object { $_.Name -eq $LabelName -or $_.DisplayName -eq $LabelName })

        if ($LabelExists) {
            $SetParams = ConvertTo-CIPPComplianceSetParams -Params $LabelParams -Identity $LabelName
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
