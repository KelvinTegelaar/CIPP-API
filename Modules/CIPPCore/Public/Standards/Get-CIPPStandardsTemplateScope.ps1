function Get-CIPPStandardsTemplateScope {
    <#
    .SYNOPSIS
        Resolves what a standards template covers, straight from its stored definition.
    .DESCRIPTION
        Get-CIPPStandards only emits the template that won the three-tier merge for each standard, so a
        report row written by a tenant-specific template still belongs to an AllTenants template that
        carries the same standard. This reads the selected template's own definition and returns the
        standard keys, Intune/CA template ids (package members included), quarantine policy names and
        reusable settings template ids it references, in the shapes the CippStandardsReports RowKeys use.
    .PARAMETER TemplateId
        RowKey of the StandardsTemplateV2 row.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TemplateId
    )

    $Scope = [PSCustomObject]@{
        StandardKeys    = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        TemplateGuids   = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        QuarantineNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    }

    $TemplatesTable = Get-CIPPTable -TableName 'templates'
    $SafeTemplateId = ConvertTo-CIPPODataFilterValue -Value $TemplateId -Type String
    $SelectedTemplate = Get-CIPPAzDataTableEntity @TemplatesTable -Filter "PartitionKey eq 'StandardsTemplateV2' and RowKey eq '$SafeTemplateId'"
    $SelectedStandards = try { ($SelectedTemplate.JSON | ConvertFrom-Json -Depth 100 -ErrorAction Stop).standards } catch { $null }
    if ($null -eq $SelectedStandards) { return $Scope }

    $PackageRows = @{}
    foreach ($Property in @($SelectedStandards.PSObject.Properties)) {
        $StandardName = $Property.Name
        $Config = $Property.Value
        switch ($StandardName) {
            { $_ -in @('IntuneTemplate', 'ConditionalAccessTemplate') } {
                $Partition = if ($_ -eq 'IntuneTemplate') { 'IntuneTemplate' } else { 'CATemplate' }
                foreach ($Item in @($Config)) {
                    if ($Item.TemplateList.value) { $null = $Scope.TemplateGuids.Add([string]$Item.TemplateList.value) }
                    foreach ($Tag in @($Item.'TemplateList-Tags')) {
                        $TagValue = if ($Tag.value) { [string]$Tag.value } else { [string]$Tag }
                        if (-not $TagValue) { continue }
                        if (-not $PackageRows.ContainsKey($Partition)) {
                            $PackageRows[$Partition] = @(Get-CIPPAzDataTableEntity @TemplatesTable -Filter "PartitionKey eq '$Partition'" | Where-Object { $_.Package })
                        }
                        foreach ($Row in ($PackageRows[$Partition] | Where-Object { $_.Package -eq $TagValue })) {
                            $null = $Scope.TemplateGuids.Add([string]$Row.RowKey)
                        }
                    }
                }
            }
            'QuarantineTemplate' {
                foreach ($Item in @($Config)) {
                    $DisplayName = $Item.displayName.value ?? $Item.displayName
                    if ($DisplayName) { $null = $Scope.QuarantineNames.Add([string]$DisplayName) }
                }
            }
            'ReusableSettingsTemplate' {
                foreach ($Item in @($Config)) {
                    foreach ($Ref in @($Item.TemplateList)) {
                        $Id = if ($Ref.value) { [string]$Ref.value } else { [string]$Ref }
                        if ($Id) { $null = $Scope.StandardKeys.Add("standards.ReusableSettingsTemplate.$Id") }
                    }
                }
            }
            default {
                $null = $Scope.StandardKeys.Add("standards.$StandardName")
            }
        }
    }

    return $Scope
}
