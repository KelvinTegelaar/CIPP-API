function Get-CIPPAlertNewRole {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [Alias('input')]
        $InputValue,
        $TenantFilter
    )
    $Deltatable = Get-CIPPTable -Table DeltaCompare
    try {
        $Filter = "PartitionKey eq 'AdminDelta' and RowKey eq '{0}'" -f $TenantFilter
        $AdminDelta = (Get-CIPPAzDataTableEntity @Deltatable -Filter $Filter).delta | ConvertFrom-Json -ErrorAction SilentlyContinue
        $NewDelta = (New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/directoryRoles?`$expand=members" -tenantid $TenantFilter) | Select-Object displayName, Members | ForEach-Object {
            @{
                GroupName = $_.displayName
                Members   = $_.Members.UserPrincipalName
                # Service principals and groups have no UPN; track them by object id, names can repeat or change.
                OtherMembers = @($_.Members | Where-Object { $_ -and -not $_.userPrincipalName } | ForEach-Object { @{ id = $_.id; name = "$($_.displayName) ($(($_.'@odata.type' -split '\.')[-1]))" } })
            }
        }
        $NewDeltatoSave = $NewDelta | ConvertTo-Json -Depth 10 -Compress -ErrorAction SilentlyContinue | Out-String
        $DeltaEntity = @{
            PartitionKey = 'AdminDelta'
            RowKey       = [string]$TenantFilter
            delta        = "$NewDeltatoSave"
        }
        Add-CIPPAzDataTableEntity @DeltaTable -Entity $DeltaEntity -Force

        if ($AdminDelta) {
            # Baselines saved before OtherMembers existed would report every existing service principal and group as new.
            $HasOtherBaseline = [bool]($AdminDelta | Where-Object { $_.PSObject.Properties['OtherMembers'] })
            $AlertData = foreach ($Group in $NewDelta) {
                $OldDelta = $AdminDelta | Where-Object { $_.GroupName -eq $Group.GroupName }
                $Added = @($Group.Members | Where-Object { $_ -notin $OldDelta.Members })
                if ($HasOtherBaseline) { $Added += @($Group.OtherMembers | Where-Object { $_.id -notin $OldDelta.OtherMembers.id }).name }
                $Added | Where-Object { $_ } | ForEach-Object {
                    [PSCustomObject]@{
                        Message = "$_ has been added to the $($Group.GroupName) Role"
                        User    = $_
                        Role    = $Group.GroupName
                        Tenant  = $TenantFilter
                    }
                }
            }
        }
        Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Alerts' -tenant $TenantFilter -message "Could not get role changes for $($TenantFilter): $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
    }
}
