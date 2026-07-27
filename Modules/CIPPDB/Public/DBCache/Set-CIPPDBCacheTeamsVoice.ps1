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
        # Keep the cached rows in step with the live list, which resolves LocationId to a label.
        $LocationLookup = Get-CippTeamsLocationLookup -TenantFilter $TenantFilter
        $Skip = 0
        $AllNumbers = [System.Collections.Generic.List[object]]::new()

        do {
            $Results = New-TeamsRequestV2 -TenantFilter $TenantFilter -Path "Skype.TelephoneNumberMgmt/Tenants/$TenantId/telephone-numbers" `
                -QueryParameters @{ skip = $Skip; locale = 'en-US'; top = 999 } `
                -AdditionalHeaders @{ 'x-ms-tnm-applicationid' = '045268c0-445e-4ac1-9157-d58f67b167d9' }
            $Data = @($Results.TelephoneNumbers | ForEach-Object {
                    $CompleteRequest = $_ | Select-Object *,
                    @{Name = 'AssignedTo'; Expression = { $Users | Where-Object -Property id -EQ $_.TargetId } },
                    @{Name = 'EmergencyLocation'; Expression = { if ($_.LocationId) { $LocationLookup[[string]$_.LocationId] } } }
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
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'TeamsVoice' -Data $PhoneNumbers -AddCount
    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Teams Voice phone numbers: $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
    }
}
