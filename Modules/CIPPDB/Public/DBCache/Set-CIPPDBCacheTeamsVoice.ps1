function Set-CIPPDBCacheTeamsVoice {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [string]$QueueId
    )

    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Teams Voice phone numbers' -sev Debug

        $TenantId = (Get-Tenants -TenantFilter $TenantFilter).customerId
        $Users = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users?`$top=999&`$select=id,userPrincipalName,displayName" -tenantid $TenantFilter
        $Skip = 0
        $AllNumbers = [System.Collections.Generic.List[object]]::new()

        do {
            $Results = New-TeamsAPIGetRequest -uri "https://api.interfaces.records.teams.microsoft.com/Skype.TelephoneNumberMgmt/Tenants/$($TenantId)/telephone-numbers?skip=$($Skip)&locale=en-US&top=999" -tenantid $TenantFilter
            $Data = @($Results.TelephoneNumbers | ForEach-Object {
                    $CompleteRequest = $_ | Select-Object *, @{Name = 'AssignedTo'; Expression = { $Users | Where-Object -Property id -EQ $_.TargetId } }
                    if ($CompleteRequest.AcquisitionDate) {
                        $CompleteRequest.AcquisitionDate = $_.AcquisitionDate -split 'T' | Select-Object -First 1
                    } else {
                        $CompleteRequest | Add-Member -NotePropertyName 'AcquisitionDate' -NotePropertyValue 'Unknown' -Force
                    }
                    if (-not $CompleteRequest.AssignedTo) {
                        $CompleteRequest | Add-Member -NotePropertyName 'AssignedTo' -NotePropertyValue 'Unassigned' -Force
                    }
                    $CompleteRequest
                })

            foreach ($Number in $Data) {
                $AllNumbers.Add($Number)
            }
            $Skip = $Skip + 999
        } while ($Data.Count -eq 999)

        $PhoneNumbers = @($AllNumbers | Where-Object { $_.TelephoneNumber })
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'TeamsVoice' -Data $PhoneNumbers
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'TeamsVoice' -Data $PhoneNumbers -Count
    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Teams Voice phone numbers: $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
    }
}
