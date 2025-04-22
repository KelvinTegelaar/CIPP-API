function Invoke-ExecPermissionRepair {
    <#
    .SYNOPSIS
        This endpoint will update the CIPP-SAM app permissions.
    .DESCRIPTION
        Merges new permissions from the SAM manifest into the AppPermissions entry for CIPP-SAM.
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.AppSettings.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    try {
        $Table = Get-CippTable -tablename 'AppPermissions'
        $User = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Request.Headers.'x-ms-client-principal')) | ConvertFrom-Json

        $CurrentPermissions = Get-CippSamPermissions
        if (($CurrentPermissions.MissingPermissions | Measure-Object).Count -gt 0) {
            Write-Information 'Missing permissions found'
            $MissingPermissions = $CurrentPermissions.MissingPermissions
            $Permissions = $CurrentPermissions.Permissions

            $AppIds = @($Permissions.PSObject.Properties.Name + $MissingPermissions.PSObject.Properties.Name)

            $NewPermissions = @{}
            foreach ($AppId in $AppIds) {
                $ApplicationPermissions = [system.collections.generic.list[object]]::new()
                $DelegatedPermissions = [system.collections.generic.list[object]]::new()

                # App permissions
                foreach ($Permission in $Permissions.$AppId.applicationPermissions) {
                    $ApplicationPermissions.Add($Permission)
                }
                if (($MissingPermissions.$AppId.applicationPermissions | Measure-Object).Count -gt 0) {
                    foreach ($MissingPermission in $MissingPermissions.$AppId.applicationPermissions) {
                        Write-Host "Adding missing permission: $MissingPermission"
                        $ApplicationPermissions.Add($MissingPermission)
                    }
                }

                # Delegated permissions
                foreach ($Permission in $Permissions.$AppId.delegatedPermissions) {
                    $DelegatedPermissions.Add($Permission)
                }
                if (($MissingPermissions.$AppId.delegatedPermissions | Measure-Object).Count -gt 0) {
                    foreach ($MissingPermission in $MissingPermissions.$AppId.delegatedPermissions) {
                        Write-Host "Adding missing permission: $MissingPermission"
                        $DelegatedPermissions.Add($MissingPermission)
                    }
                }
                # New permission object
                $NewPermissions.$AppId = @{
                    applicationPermissions = @($ApplicationPermissions | Sort-Object -Property label)
                    delegatedPermissions   = @($DelegatedPermissions | Sort-Object -Property label)
                }
            }


            $Entity = @{
                'PartitionKey' = 'CIPP-SAM'
                'RowKey'       = 'CIPP-SAM'
                'Permissions'  = [string]([PSCustomObject]$NewPermissions | ConvertTo-Json -Depth 10 -Compress)
                'UpdatedBy'    = $User.UserDetails ?? 'CIPP-API'
            }
            $Table = Get-CIPPTable -TableName 'AppPermissions'
            $null = Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force

            $Body = @{
                'Results' = 'Permissions Updated'
            }
            Write-LogMessage -headers $Request.Headers -API 'ExecPermissionRepair' -message 'CIPP-SAM Permissions Updated' -Sev 'Info' -LogData $Permissions
        } else {
            $Body = @{
                'Results' = 'No permissions to update'
            }
        }
    } catch {
        $Body = @{
            'Results' = "$($_.Exception.Message) - at line $($_.InvocationInfo.ScriptLineNumber)"
        }
    }

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })
}
