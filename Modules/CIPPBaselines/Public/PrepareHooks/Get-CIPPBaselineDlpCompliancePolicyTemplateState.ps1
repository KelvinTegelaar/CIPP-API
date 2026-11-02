function Get-CIPPBaselineDlpCompliancePolicyTemplateState {
    <#
    .SYNOPSIS
        Prepare hook for DlpCompliancePolicyTemplate: this instance's DLP policy sync state.
    .DESCRIPTION
        One instance grades ONE template (instanceIdentity), resolved from the
        DlpCompliancePolicyTemplate partition. Compare-CIPPDlpCompliancePolicy diffs the
        template against the live policy and its rules field by field through the same
        normalization the deploy path uses, so a policy deployed from the template
        collapses to InSync.

        Missing, Drift and PendingDeletion are non-compliant; only Missing and Drift are
        remediable - a PendingDeletion policy cannot be modified, so deploying it would
        just fail and it is surfaced instead, exactly the classic's handling. The graded
        list carries a compact projection (name, state, differing Scope/Field pairs); the
        full template is carried separately for the executor.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $Reference = $Item.Variables.dlpCompliancePolicyTemplate
    if ($Reference -is [System.Management.Automation.PSCustomObject] -and $Reference.PSObject.Properties.Name -contains 'value') { $Reference = $Reference.value }
    if ([string]::IsNullOrWhiteSpace("$Reference")) { return @{ Current = $null } }

    $Table = Get-CippTable -tablename 'templates'
    $SafeReference = ConvertTo-CIPPODataFilterValue -Value "$Reference"
    $Entity = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'DlpCompliancePolicyTemplate' and RowKey eq '$SafeReference'" | Select-Object -First 1
    $Template = $(if ($Entity -and -not [string]::IsNullOrWhiteSpace($Entity.JSON)) { try { $Entity.JSON | ConvertFrom-Json -Depth 50 -ErrorAction Stop } catch { $null } })
    if (-not $Template) { return @{ Current = $null } }

    $Comparison = try {
        Compare-CIPPDlpCompliancePolicy -TenantFilter $TenantFilter -Template $Template -ErrorAction Stop
    } catch {
        Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Could not compare DLP policy '$($Template.Name ?? $Template.name)': $($_.Exception.Message)" -Sev 'Error'
        return @{ Current = $null }
    }
    if (-not $Comparison) { return @{ Current = $null } }

    $NonCompliant = @(if ("$($Comparison.State)" -ne 'InSync') {
            [PSCustomObject]@{
                Name   = "$($Comparison.Name)"
                State  = "$($Comparison.State)"
                Fields = @($Comparison.Differences | ForEach-Object { "$($_.Scope)/$($_.Field)" })
            }
        })
    $Remediable = @(if ("$($Comparison.State)" -in @('Missing', 'Drift')) { $Template })

    $Current = [PSCustomObject]@{ nonCompliantDlpPolicies = @($NonCompliant) }
    # Carried for the executor, not graded.
    $Current | Add-Member -NotePropertyName 'remediableTemplates' -NotePropertyValue @($Remediable)

    @{
        Expected = [PSCustomObject]@{ nonCompliantDlpPolicies = @() }
        Current  = $Current
    }
}
