function Get-CIPPAlertNewRole {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $false)]
        $input,
        $TenantFilter
    )
    $Deltatable = Get-CIPPTable -Table DeltaCompare
    try {
        $Filter = "PartitionKey eq 'AdminDelta' and RowKey eq '{0}'" -f $TenantFilter
        $AdminDelta = (Get-CIPPAzDataTableEntity @Deltatable -Filter $Filter).delta | ConvertFrom-Json -ErrorAction SilentlyContinue
        $NewDelta = (New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/directoryRoles?`$expand=members" -tenantid $TenantFilter) | Select-Object displayname, Members | ForEach-Object {
            @{
                GroupName = $_.displayname
                Members   = $_.Members.UserPrincipalName
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
            $AlertData = foreach ($Group in $NewDelta) {
                $OldDelta = $AdminDelta | Where-Object { $_.GroupName -eq $Group.GroupName }
                $Group.members | Where-Object { $_ -notin $OldDelta.members } | ForEach-Object {
                    "$_ has been added to the $($Group.GroupName) Role"
                }
            }
            Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData
        }
    } catch {
        Write-AlertMessage -tenant $($TenantFilter) -message "Could not get get role changes for $($TenantFilter): $(Get-NormalizedError -message $_.Exception.message)"
    }
}
