function Import-CIPPBaselineTemplate {
    <#
    .SYNOPSIS
        Imports a BaselineTemplate file from a community repo, related templates first.
    .DESCRIPTION
        The baseline counterpart of the CA policy's named-locations pattern: the
        baseline file carries a referencedTemplates manifest, and this function fetches
        each referenced CA/Intune template file from the SAME repository and runs it
        through the untouched Import-CommunityTemplate path (which preserves the file's
        own RowKey/GUID - critical, because the baseline's standard instances reference
        templates by exactly those ids). Only then is the baseline itself created via
        New-CIPPBaseline, keeping the exported placeholder assignment ('Exported
        Template') so the operator must consciously assign real tenants.
        Re-imports dedupe by (Source, templateName) on the rollout row with the same
        SHA-guard semantics as template imports: same blob sha -> skip unless -Force;
        a match updates the existing baseline in place (same GUID) so triage and
        resolved rows survive an upstream update.
        Missing referenced files fall back to a tree lookup by sanitized display name
        under the partition folder; still-missing ones are reported, never fatal.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Baseline,
        $FullName,
        $Branch,
        $SHA,
        $User,
        [switch]$Force
    )

    if (-not $Baseline.templateName) { throw 'The baseline file carries no templateName.' }

    # Re-import dedupe: same repo + same name = the same baseline, updated in place.
    $RolloutTable = Get-CippTable -tablename 'BaselineRollouts'
    $SafeSource = ConvertTo-CIPPODataFilterValue -Value "$FullName"
    $Existing = Get-CIPPAzDataTableEntity @RolloutTable -Filter "PartitionKey eq 'rollout' and Source eq '$SafeSource'" |
        Where-Object { $_.templateName -eq "$($Baseline.templateName)" } | Select-Object -First 1
    if ($Existing -and "$($Existing.SHA)" -eq "$SHA" -and -not $Force) {
        return "Baseline '$($Baseline.templateName)' is already up to date. Skipping import."
    }

    # Related templates first, so the baseline's references resolve the moment it lands.
    $Tree = $null
    $ImportedCount = 0
    $Failures = [System.Collections.Generic.List[string]]::new()
    foreach ($Reference in @($Baseline.referencedTemplates)) {
        if (-not $Reference) { continue }
        try {
            $File = $null
            if ("$($Reference.path)") {
                try { $File = Get-GitHubFileContents -FullName $FullName -Path $Reference.path -Branch $Branch } catch { $File = $null }
            }
            if (-not $File) {
                # The file moved or was renamed: find it by sanitized display name under
                # its partition folder - the same convention every upload writes with.
                if (-not $Tree) { $Tree = @((Get-GitHubFileTree -FullName $FullName -Branch $Branch).tree) }
                $Sanitized = "$($Reference.displayName)" -replace '\s', '_' -replace '[^\w\d_]', ''
                $Candidate = $Tree | Where-Object {
                    $_.path -match '\.json$' -and $_.path -like "$($Reference.partition)/*" -and
                    (((($_.path -split '/')[-1]) -replace '\.json$', '') -eq $Sanitized)
                } | Select-Object -First 1
                if ($Candidate) { $File = Get-GitHubFileContents -FullName $FullName -Path $Candidate.path -Branch $Branch }
            }
            if (-not $File) {
                $Failures.Add("$($Reference.displayName) ($($Reference.partition)) was not found in the repository")
                continue
            }
            $Content = $File.content | ConvertFrom-Json -Depth 100
            $null = Import-CommunityTemplate -Template $Content -SHA $File.sha -Source $FullName -Force:$Force
            $ImportedCount++
        } catch {
            $Failures.Add("$($Reference.displayName): $($_.Exception.Message)")
        }
    }

    $Payload = [PSCustomObject]@{
        GUID            = $(if ($Existing) { $Existing.RowKey } else { $null })
        templateName    = "$($Baseline.templateName)"
        description     = "$($Baseline.description)"
        assignedTenants = @($Baseline.assignedTenants)
        excludedTenants = @()
        alertEmails     = ''
        alertWebhookUrl = ''
        stages          = @($Baseline.stages)
    }
    $Saved = New-CIPPBaseline -Baseline $Payload -User ("$User" ? "$User" : 'GitHub Import') -Source "$FullName" -SHA "$SHA"

    $Message = "Imported baseline '$($Baseline.templateName)' ($($Saved.DeltaCount) delta rows) with $ImportedCount related template$(if ($ImportedCount -eq 1) { '' } else { 's' }). Assign it to real tenants in the editor - it arrives assigned to the 'Exported Template' placeholder."
    if ($Failures.Count -gt 0) {
        $Message = "$Message Missing: $($Failures -join '; ')."
    }
    $Message
}
