function Get-CIPPBaselineReusableSettingsTemplateState {
    <#
    .SYNOPSIS
        Prepare hook for ReusableSettingsTemplate: is this instance's reusable setting
        deployed and in sync.
    .DESCRIPTION
        One instance grades ONE template. The deep diff runs through
        Compare-CIPPIntuneObject with compareType 'ReusablePolicySetting' - the SAME
        comparer, same compareType, the classic used. The classic also null-stripped both
        sides first; that is omitted here because the comparer already treats null, empty
        and absent as equal in every branch - verified empirically - so the strip changed
        no verdict.

        The cache carries settingInstance explicitly: the list endpoint omits it unless
        selected, and without it every compare would fail exactly as the classic's own
        comment warns.

        Template resolution stays per-family: PartitionKey 'IntuneReusableSettingTemplate'
        (one of the three partitions that do NOT match their standard name), name from
        DisplayName ?? Name, body from RawJSON ?? JSON.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $Settings = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'IntuneReusableSettings')
    if ($Settings.Count -eq 0 -and -not (Test-CIPPBaselineCacheCollected -TenantFilter $TenantFilter -Type 'IntuneReusableSettings')) {
        return @{ Current = $null }
    }

    $Reference = $Item.Variables.reusableSettingsTemplate
    if ($Reference -is [System.Management.Automation.PSCustomObject] -and $Reference.PSObject.Properties.Name -contains 'value') { $Reference = $Reference.value }
    if ([string]::IsNullOrWhiteSpace("$Reference")) { return @{ Current = $null } }

    $Table = Get-CippTable -tablename 'templates'
    $SafeReference = ConvertTo-CIPPODataFilterValue -Value "$Reference"
    $Entity = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'IntuneReusableSettingTemplate' and RowKey eq '$SafeReference'" | Select-Object -First 1
    $Template = $(if ($Entity -and -not [string]::IsNullOrWhiteSpace($Entity.JSON)) { try { $Entity.JSON | ConvertFrom-Json -Depth 50 -ErrorAction Stop } catch { $null } })
    if (-not $Template) { return @{ Current = $null } }

    $DisplayName = "$($Template.DisplayName ?? $Template.Name)"
    $RawJSON = $Template.RawJSON ?? $Template.JSON
    $Body = $(try { $RawJSON | ConvertFrom-Json -Depth 50 -ErrorAction Stop } catch { $null })
    if ([string]::IsNullOrWhiteSpace($DisplayName) -or -not $Body) { return @{ Current = $null } }

    $Existing = $Settings | Where-Object { "$($_.displayName)" -eq $DisplayName } | Select-Object -First 1

    if (-not $Existing) {
        $Current = [PSCustomObject]@{ deployed = $false; drift = @() }
        $Current | Add-Member -NotePropertyName 'rawJSON' -NotePropertyValue "$RawJSON"
        $Current | Add-Member -NotePropertyName 'existingId' -NotePropertyValue $null
        return @{
            Expected = [PSCustomObject]@{ deployed = $true; drift = @() }
            Current  = $Current
        }
    }

    $Differences = try {
        $ExistingSanitized = $Existing | Select-Object -Property * -ExcludeProperty id, createdDateTime, lastModifiedDateTime, version, referencingConfigurationPolicyCount, '*odata*'
        @(Compare-CIPPIntuneObject -ReferenceObject $Body -DifferenceObject $ExistingSanitized -compareType 'ReusablePolicySetting' -ErrorAction Stop | Where-Object { $_ })
    } catch {
        # A failed compare is not drift - report unknown rather than inventing a verdict.
        Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Could not compare reusable setting '$DisplayName': $($_.Exception.Message)" -Sev 'Error'
        return @{ Current = $null }
    }

    $Current = [PSCustomObject]@{
        deployed = $true
        drift    = @($Differences | ForEach-Object { "$($_.Property ?? $_.Setting ?? $_)" })
    }
    # Carried for the executor, not graded.
    $Current | Add-Member -NotePropertyName 'rawJSON' -NotePropertyValue "$RawJSON"
    $Current | Add-Member -NotePropertyName 'existingId' -NotePropertyValue "$($Existing.id)"

    @{
        Expected = [PSCustomObject]@{ deployed = $true; drift = @() }
        Current  = $Current
    }
}
