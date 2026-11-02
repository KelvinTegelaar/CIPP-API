function Set-CIPPDlpCompliancePolicy {
    <#
    .SYNOPSIS
        Deploy or update a single DLP compliance policy (+ optional rule) in a tenant from a template object.
    .DESCRIPTION
        Single source of truth for deploying DLP compliance policies. Both the HTTP deploy endpoint
        (Invoke-AddDlpCompliancePolicy) and the standard (Invoke-CIPPStandardDlpCompliancePolicyTemplate)
        call into this so the deploy logic, allowlists, location normalization, Set-vs-New decision, and
        built-in skip behavior all live in one place.
    .PARAMETER TenantFilter
        Target tenant (defaultDomainName or customerId).
    .PARAMETER Template
        Source template object — typically the JSON from a stored template or a PowerShellCommand body,
        already parsed with ConvertFrom-Json.
    .PARAMETER APIName
        Caller's API name, used for log messages.
    .PARAMETER Headers
        Optional request headers, used for log messages on HTTP-driven calls.
    .OUTPUTS
        String result message describing what happened (Created / Updated / Skipped / Failed ...).
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

    # Allowlists come from the single shared source so deploy, template creation, and drift comparison
    # never diverge. Priority is excluded there (per-tenant), and rules carry no 'Mode' (policy-level).
    $Fields = Get-CIPPDlpComplianceFieldList
    $PolicyAllowedFields = $Fields.Policy
    $RuleAllowedFields = $Fields.Rule
    $LocationFields = $Fields.Location

    $PolicyParams = Format-CIPPCompliancePolicyParams -Source $Template -AllowedFields $PolicyAllowedFields -LocationFields $LocationFields
    # Drop a Mode the cmdlets won't accept as input (e.g. 'PendingDeletion' captured from a policy that
    # was mid-deletion); New-/Set-* would otherwise throw InvalidCompliancePolicyMode.
    if ($PolicyParams.ContainsKey('Mode') -and $PolicyParams['Mode'] -notin $Fields.ValidPolicyModes) {
        $PolicyParams.Remove('Mode') | Out-Null
    }
    $RuleSource = $Template.RuleParams
    $PolicyName = $PolicyParams.Name

    try {
        # Pull the location fields too so re-deploys can diff against what the policy already has.
        $ExistingPolicies = try { New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-DlpCompliancePolicy' -Compliance | Select-Object (@('Name', 'IsDefault') + $LocationFields) } catch { @() }
        $ExistingRules = try { New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-DlpComplianceRule' -Compliance | Select-Object Name, ParentPolicyName } catch { @() }

        $ExistingPolicy = $ExistingPolicies | Where-Object { $_.Name -eq $PolicyName } | Select-Object -First 1
        if ($ExistingPolicy -and $ExistingPolicy.IsDefault) {
            $msg = "DLP compliance policy '$PolicyName' is a Microsoft built-in and cannot be modified — skipping in $TenantFilter."
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $msg -sev Warning
            return $msg
        }

        if ($ExistingPolicy) {
            # Location params are Add-prefixed on Set (incremental), so re-adding a location the policy
            # already has (e.g. 'All') throws LocationAlreadyExistsException and aborts the entire Set.
            # Diff each location field against the existing policy and only Add what's genuinely new.
            $DeltaParams = @{}
            foreach ($key in $PolicyParams.Keys) {
                if ($key -notin $LocationFields) { $DeltaParams[$key] = $PolicyParams[$key]; continue }
                $existingLocs = @($ExistingPolicy.$key) | ForEach-Object {
                    if ($null -eq $_) { return }
                    if ($_ -is [string]) { $_ }
                    elseif ($_.Name) { $_.Name }
                    elseif ($_.DisplayName) { $_.DisplayName }
                    elseif ($_.PrimarySmtpAddress) { $_.PrimarySmtpAddress }
                }
                $newLocs = @($PolicyParams[$key]) | Where-Object { $_ -and $_ -notin $existingLocs }
                if ($newLocs.Count -gt 0) { $DeltaParams[$key] = $newLocs }
            }
            $SetParams = ConvertTo-CIPPComplianceSetParams -Params $DeltaParams -Identity $PolicyName -AddPrefixFields $LocationFields
            $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-DlpCompliancePolicy' -cmdParams $SetParams -Compliance -useSystemMailbox $true
            $PolicyAction = "Updated DLP compliance policy '$PolicyName' in $TenantFilter."
        } else {
            $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'New-DlpCompliancePolicy' -cmdParams $PolicyParams -Compliance -useSystemMailbox $true
            $PolicyAction = "Created DLP compliance policy '$PolicyName' in $TenantFilter."
        }

        # RuleParams may be a single rule object (legacy templates) or an array of rules - a DLP
        # policy can carry several (e.g. low- vs high-volume detection). Normalize to an array.
        $RuleList = @($RuleSource) | Where-Object { $_ }
        $RuleActions = @()
        $RuleIndex = 0
        foreach ($Rule in $RuleList) {
            $RuleIndex++
            $RuleHash = Format-CIPPCompliancePolicyParams -Source $Rule -AllowedFields $RuleAllowedFields
            # Advanced-mode rules send only the AdvancedRule JSON blob, simple-mode rules only the flat
            # condition params - New-/Set-DlpComplianceRule reject a mix (see Resolve-CIPPDlpAdvancedRule).
            $RuleHash = Resolve-CIPPDlpAdvancedRule -Source $Rule -RuleParams $RuleHash
            foreach ($SitField in @('ContentContainsSensitiveInformation', 'ExceptIfContentContainsSensitiveInformation')) {
                if ($RuleHash.ContainsKey($SitField)) {
                    $RuleHash[$SitField] = @(ConvertTo-CIPPSensitiveInformationType -SensitiveInformation $RuleHash[$SitField])
                }
            }
            # Get-* returns IncidentReportContent as a single comma-joined string, but the New-/Set-*
            # cmdlets expect a ReportContentOption[] array - split it back out.
            if ($RuleHash.ContainsKey('IncidentReportContent') -and $RuleHash['IncidentReportContent'] -is [string]) {
                $RuleHash['IncidentReportContent'] = @($RuleHash['IncidentReportContent'] -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
            }
            $RuleHash['Policy'] = $PolicyName
            $RuleName = if ($RuleHash.ContainsKey('Name') -and -not [string]::IsNullOrWhiteSpace([string]$RuleHash['Name'])) {
                $RuleHash['Name']
            } elseif ($RuleList.Count -gt 1) {
                "$PolicyName Rule $RuleIndex"
            } else {
                "$PolicyName Rule"
            }
            $RuleHash['Name'] = $RuleName

            # DLP rule names are unique tenant-wide, so match on BOTH name and parent policy:
            #  - same name under THIS policy        -> update it (idempotent re-deploy)
            #  - same name under a DIFFERENT policy -> conflict; skip rather than clobber that policy's
            #                                          rule (the name must be made unique to deploy here)
            #  - name free                          -> create it
            $RuleUnderThisPolicy = $ExistingRules | Where-Object { $_.Name -eq $RuleName -and $_.ParentPolicyName -eq $PolicyName }
            $RuleNameOwnedElsewhere = $ExistingRules | Where-Object { $_.Name -eq $RuleName -and $_.ParentPolicyName -ne $PolicyName } | Select-Object -First 1

            if ($RuleUnderThisPolicy) {
                $SetRuleHash = ConvertTo-CIPPComplianceSetParams -Params $RuleHash -Identity $RuleName
                $SetRuleHash.Remove('Policy') | Out-Null
                $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-DlpComplianceRule' -cmdParams $SetRuleHash -Compliance -useSystemMailbox $true
                $RuleActions += "updated rule '$RuleName'"
            } elseif ($RuleNameOwnedElsewhere) {
                $Warn = "rule '$RuleName' already exists under policy '$($RuleNameOwnedElsewhere.ParentPolicyName)' - rule names must be unique tenant-wide, so it was NOT created for '$PolicyName'"
                Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Warn -sev Warning
                $RuleActions += $Warn
            } else {
                $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'New-DlpComplianceRule' -cmdParams $RuleHash -Compliance -useSystemMailbox $true
                $RuleActions += "created rule '$RuleName'"
            }
        }

        $Result = if ($RuleActions.Count -gt 0) { "$PolicyAction Rules: $($RuleActions -join '; ')." } else { $PolicyAction }
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -sev Info
        return $Result
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $msg = "Could not deploy DLP compliance policy '$PolicyName' to $($TenantFilter): $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $msg -sev Error -LogData $ErrorMessage
        return $msg
    }
}
