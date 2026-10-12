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
        $UserById = @{}
        New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users?`$top=999&`$select=id,userPrincipalName,displayName" -tenantid $TenantFilter -Stream | ForEach-Object { $UserById[$_.id] = $_ }
        # Keep the cached rows in step with the live list, which resolves LocationId to a label.
        $LocationLookup = Get-CippTeamsLocationLookup -TenantFilter $TenantFilter
        $Skip = 0
        $AllNumbers = [System.Collections.Generic.List[object]]::new()

        do {
            $Results = New-TeamsRequestV2 -TenantFilter $TenantFilter -Path "Skype.TelephoneNumberMgmt/Tenants/$TenantId/telephone-numbers" `
                -QueryParameters @{ skip = $Skip; locale = 'en-US'; top = 999 } `
                -AdditionalHeaders @{ 'x-ms-tnm-applicationid' = '045268c0-445e-4ac1-9157-d58f67b167d9' }
            $Data = @(foreach ($Number in $Results.TelephoneNumbers) {
                    # What Select-Object *, AssignedTo, EmergencyLocation built, without a pipeline per number
                    $Row = [ordered]@{}
                    foreach ($Property in $Number.PSObject.Properties) { $Row[$Property.Name] = $Property.Value }
                    if (-not $Row.Contains('AssignedTo')) { $Row['AssignedTo'] = if ($Number.TargetId) { $UserById[[string]$Number.TargetId] } }
                    if (-not $Row.Contains('EmergencyLocation')) { $Row['EmergencyLocation'] = if ($Number.LocationId) { $LocationLookup[[string]$Number.LocationId] } }
                    $CompleteRequest = [PSCustomObject]$Row
                    $Props = $CompleteRequest.PSObject.Properties
                    if ($CompleteRequest.AcquisitionDate) {
                        $CompleteRequest.AcquisitionDate = ($Number.AcquisitionDate -split 'T')[0]
                    } else {
                        $Props.Remove('AcquisitionDate'); $Props.Add([psnoteproperty]::new('AcquisitionDate', 'Unknown'))
                    }
                    if (-not $CompleteRequest.AssignedTo) {
                        $Props.Remove('AssignedTo'); $Props.Add([psnoteproperty]::new('AssignedTo', 'Unassigned'))
                    }
                    $CompleteRequest
                })

            foreach ($Number in $Data) {
                $AllNumbers.Add($Number)
            }
            $Skip = $Skip + 999
        } while ($Data.Count -eq 999)

        $PhoneNumbers = @($AllNumbers.Where({ $_.TelephoneNumber }))
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'TeamsVoice' -Data $PhoneNumbers -AddCount
    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Teams Voice phone numbers: $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
    }
}
