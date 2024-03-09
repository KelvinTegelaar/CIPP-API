function Push-CIPPAlertNewRole {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        $Item
    )
    $Deltatable = Get-CIPPTable -Table DeltaCompare
    try {
        $Filter = "PartitionKey eq 'AdminDelta' and RowKey eq '{0}'" -f $Item.tenantid
        $AdminDelta = (Get-CIPPAzDataTableEntity @Deltatable -Filter $Filter).delta | ConvertFrom-Json -ErrorAction SilentlyContinue
        $NewDelta = (New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/directoryRoles?`$expand=members" -tenantid $Item.tenant) | Select-Object displayname, Members | ForEach-Object {
            @{
                GroupName = $_.displayname
                Members   = $_.Members.UserPrincipalName
            }
        }
        $NewDeltatoSave = $NewDelta | ConvertTo-Json -Depth 10 -Compress -ErrorAction SilentlyContinue | Out-String
        $DeltaEntity = @{
            PartitionKey = 'AdminDelta'
            RowKey       = [string]$Item.tenantid
            delta        = "$NewDeltatoSave"
        }
        Add-CIPPAzDataTableEntity @DeltaTable -Entity $DeltaEntity -Force

        if ($AdminDelta) {
            foreach ($Group in $NewDelta) {
                $OldDelta = $AdminDelta | Where-Object { $_.GroupName -eq $Group.GroupName }
                $Group.members | Where-Object { $_ -notin $OldDelta.members } | ForEach-Object {
                    Write-AlertMessage -tenant $($Item.tenant) -message "$_ has been added to the $($Group.GroupName) Role"
                }
            }
        }
    } catch {
        Write-AlertMessage -tenant $($Item.tenant) -message "Could not get get role changes for $($Item.tenant): $(Get-NormalizedError -message $_.Exception.message)"
    }
}
