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

                # Persist the full applied set = manifest base ∪ submitted extras, so the AppPermissions
                # table always reflects everything the CIPP-SAM app should have (the manifest is always
                # applied and cannot be removed). Get-CippSamPermissions diffs the manifest against this
                # table to decide when a Permissions repair is needed.
                $Applied = @{}
                $AppIds = @(@($ManifestPermissions.PSObject.Properties.Name) + @($Submitted.PSObject.Properties.Name)) | Where-Object { $_ } | Sort-Object -Unique
                foreach ($AppId in $AppIds) {
                    $ManifestApp = $ManifestPermissions.$AppId
                    $ManifestAppIds = @($ManifestApp.applicationPermissions.id)
                    $ManifestDelIds = @($ManifestApp.delegatedPermissions.id)

                    $AppPerms = [System.Collections.Generic.List[object]]::new()
                    $DelPerms = [System.Collections.Generic.List[object]]::new()

                    foreach ($Permission in $ManifestApp.applicationPermissions) {
                        $AppPerms.Add([PSCustomObject]@{ id = $Permission.id; value = $Permission.value })
                    }
                    foreach ($Permission in $ManifestApp.delegatedPermissions) {
                        $DelPerms.Add([PSCustomObject]@{ id = $Permission.id; value = $Permission.value })
                    }
                    foreach ($Permission in $Submitted.$AppId.applicationPermissions) {
                        if ($Permission.id -and $ManifestAppIds -notcontains $Permission.id) {
                            $AppPerms.Add([PSCustomObject]@{ id = $Permission.id; value = $Permission.value })
                        }
                    }
                    foreach ($Permission in $Submitted.$AppId.delegatedPermissions) {
                        if ($Permission.id -and $ManifestDelIds -notcontains $Permission.id) {
                            $DelPerms.Add([PSCustomObject]@{ id = $Permission.id; value = $Permission.value })
                        }
                    }

                    if ($AppPerms.Count -gt 0 -or $DelPerms.Count -gt 0) {
                        $Applied.$AppId = @{
                            applicationPermissions = @($AppPerms)
                            delegatedPermissions   = @($DelPerms)
                        }
                    }
                }

                $Entity = @{
                    'PartitionKey' = 'CIPP-SAM'
                    'RowKey'       = 'CIPP-SAM'
                    'Permissions'  = [string]([PSCustomObject]$Applied | ConvertTo-Json -Depth 10 -Compress)
                    'UpdatedBy'    = $User.UserDetails ?? 'CIPP-API'
                }
                $Table = Get-CIPPTable -TableName 'AppPermissions'
                $null = Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force
                $Body = @{
                    'Results' = 'Permissions updated. Default CIPP permissions are always applied and cannot be removed. Please run a Permissions check and CPV refresh to finalise the changes.'
                }
                Write-LogMessage -headers $Request.Headers -API 'ExecSAMAppPermissions' -message 'CIPP-SAM permissions updated' -Sev 'Info' -LogData $Applied
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
