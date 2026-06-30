function Invoke-ExecSAMAppPermissions {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.SuperAdmin.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $User = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Request.Headers.'x-ms-client-principal')) | ConvertFrom-Json

    switch ($Request.Query.Action) {
        'Update' {
            try {
                $Submitted = $Request.Body.Permissions
                $ManifestPermissions = (Get-CippSamPermissions -ManifestOnly).Permissions

                $Extras = @{}
                foreach ($AppId in $Submitted.PSObject.Properties.Name) {
                    $ManifestApp = $ManifestPermissions.$AppId
                    $ManifestAppIds = @($ManifestApp.applicationPermissions.id)
                    $ManifestDelIds = @($ManifestApp.delegatedPermissions.id)

                    $ExtraApp = @(foreach ($Permission in $Submitted.$AppId.applicationPermissions) {
                            if ($Permission.id -and $ManifestAppIds -notcontains $Permission.id) {
                                [PSCustomObject]@{ id = $Permission.id; value = $Permission.value }
                            }
                        })
                    $ExtraDel = @(foreach ($Permission in $Submitted.$AppId.delegatedPermissions) {
                            if ($Permission.id -and $ManifestDelIds -notcontains $Permission.id) {
                                [PSCustomObject]@{ id = $Permission.id; value = $Permission.value }
                            }
                        })

                    if ($ExtraApp.Count -gt 0 -or $ExtraDel.Count -gt 0) {
                        $Extras.$AppId = @{
                            applicationPermissions = $ExtraApp
                            delegatedPermissions   = $ExtraDel
                        }
                    }
                }

                $Entity = @{
                    'PartitionKey' = 'CIPP-SAM'
                    'RowKey'       = 'CIPP-SAM'
                    'Permissions'  = [string]([PSCustomObject]$Extras | ConvertTo-Json -Depth 10 -Compress)
                    'UpdatedBy'    = $User.UserDetails ?? 'CIPP-API'
                }
                $Table = Get-CIPPTable -TableName 'AppPermissions'
                $null = Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force
                $Body = @{
                    'Results' = 'Additional permissions updated. Default CIPP permissions are always applied and cannot be removed. Please run a Permissions check and CPV refresh to finalise the changes.'
                }
                Write-LogMessage -headers $Request.Headers -API 'ExecSAMAppPermissions' -message 'CIPP-SAM additional permissions updated' -Sev 'Info' -LogData $Extras
            } catch {
                $Body = @{
                    'Results' = $_.Exception.Message
                }
            }
        }
        'Reset' {
            try {
                $Table = Get-CIPPTable -TableName 'AppPermissions'
                $Existing = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'CIPP-SAM' and RowKey eq 'CIPP-SAM'"
                if ($Existing) {
                    $null = Remove-AzDataTableEntity @Table -Entity $Existing -Force
                }
                $Body = @{
                    'Results' = 'Permissions reset to CIPP defaults.'
                }
                Write-LogMessage -headers $Request.Headers -API 'ExecSAMAppPermissions' -message 'CIPP-SAM permissions reset to CIPP defaults' -Sev 'Info'
            } catch {
                $Body = @{
                    'Results' = $_.Exception.Message
                }
            }
        }
        default {
            $Body = Get-CippSamPermissions
        }
    }


    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = ConvertTo-Json -Depth 10 -InputObject $Body
        })

}
