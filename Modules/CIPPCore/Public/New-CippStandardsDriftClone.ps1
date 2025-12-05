function New-CippStandardsDriftClone {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][string]$TemplateId,
        [Parameter(Mandatory)][switch]$UpgradeToDrift,
        $Headers
    )

    $Table = Get-CippTable -tablename 'templates'
    $Filter = "PartitionKey eq 'StandardsTemplateV2' and RowKey eq '$TemplateId'"
    $Entity = Get-CIPPAzDataTableEntity @Table -Filter $Filter
    $data = $Entity.JSON | ConvertFrom-Json
    $data.excludedTenants = @() #blank excluded Tenants
    $data.tenantFilter = @(@{ value = 'Copied Standard'; label = 'Copied Standard' })
    $data.GUID = [guid]::NewGuid().ToString()
    $data.templateName = "$($data.templateName) (Drift Clone)"
    if ($UpgradeToDrift) {
        try {
            $data | Add-Member -MemberType NoteProperty -Name 'type' -Value 'drift' -Force
            if ($null -ne $data.standards) {
                foreach ($prop in $data.standards.PSObject.Properties) {
                    $actions = $prop.Value.action
                    if ($actions -and $actions.Count -gt 0) {
                        if ($actions | Where-Object { $_.value -eq 'remediate' }) {
                            $prop.Value | Add-Member -MemberType NoteProperty -Name 'autoRemediate' -Value $true -Force
                        }
                        # Set action to Report using add-member to avoid issues with readonly arrays
                        $prop.Value | Add-Member -MemberType NoteProperty -Name 'action' -Value @(@{ 'label' = 'Report'; 'value' = 'Report' }) -Force
                    }
                }
            }
            $Entity.JSON = "$(ConvertTo-Json -InputObject $data -Compress -Depth 100)"
            $Entity.RowKey = "$($data.GUID)"
            $Entity.GUID = $data.GUID
            $update = Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force
            return 'Clone Completed successfully'
        } catch {
            return "Failed to Clone template to Drift Template: $_"
        }
    }
}
