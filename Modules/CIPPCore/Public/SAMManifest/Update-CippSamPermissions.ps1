function Update-CippSamPermissions {
    <#
    .SYNOPSIS
        Updates CIPP-SAM app permissions by merging missing permissions.
    .DESCRIPTION
        Retrieves current SAM permissions, merges any missing permissions, and updates the AppPermissions table.
    .PARAMETER UpdatedBy
        The user or system that is performing the update. Defaults to 'CIPP-API'.
    .OUTPUTS
        String indicating the result of the operation.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$UpdatedBy = 'CIPP-API'
    )

    try {
        $CurrentPermissions = Get-CippSamPermissions

        if (($CurrentPermissions.MissingPermissions | Measure-Object).Count -eq 0) {
            return 'No permissions to update'
        }

        Write-Information 'Missing permissions found'
        $MissingPermissions = $CurrentPermissions.MissingPermissions
        $Permissions = $CurrentPermissions.Permissions

        $AppIds = @($Permissions.PSObject.Properties.Name + $MissingPermissions.PSObject.Properties.Name)
        $NewPermissions = @{}

        foreach ($AppId in $AppIds) {
            if (!$AppId) { continue }
            $ApplicationPermissions = [system.collections.generic.list[object]]::new()
            $DelegatedPermissions = [system.collections.generic.list[object]]::new()

            foreach ($Permission in $Permissions.$AppId.applicationPermissions) {
                $ApplicationPermissions.Add($Permission)
            }
            if (($MissingPermissions.$AppId.applicationPermissions | Measure-Object).Count -gt 0) {
                foreach ($MissingPermission in $MissingPermissions.$AppId.applicationPermissions) {
                    Write-Host "Adding missing permission: $MissingPermission"
                    $ApplicationPermissions.Add($MissingPermission)
                }
            }

            foreach ($Permission in $Permissions.$AppId.delegatedPermissions) {
                $DelegatedPermissions.Add($Permission)
            }
            if (($MissingPermissions.$AppId.delegatedPermissions | Measure-Object).Count -gt 0) {
                foreach ($MissingPermission in $MissingPermissions.$AppId.delegatedPermissions) {
                    Write-Host "Adding missing permission: $MissingPermission"
                    $DelegatedPermissions.Add($MissingPermission)
                }
            }

            $NewPermissions.$AppId = @{
                applicationPermissions = @($ApplicationPermissions | Sort-Object -Property label)
                delegatedPermissions   = @($DelegatedPermissions | Sort-Object -Property label)
            }
        }

        $Entity = @{
            'PartitionKey' = 'CIPP-SAM'
            'RowKey'       = 'CIPP-SAM'
            'Permissions'  = [string]([PSCustomObject]$NewPermissions | ConvertTo-Json -Depth 10 -Compress)
            'UpdatedBy'    = $UpdatedBy
        }

        $Table = Get-CIPPTable -TableName 'AppPermissions'
        $null = Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force

        Write-LogMessage -API 'UpdateCippSamPermissions' -message 'CIPP-SAM Permissions Updated' -Sev 'Info' -LogData $NewPermissions

        return 'Permissions Updated'
    } catch {
        throw "Failed to update permissions: $($_.Exception.Message)"
    }
}
