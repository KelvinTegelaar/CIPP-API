function Push-ListTeamsVoiceAllTenants {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    param($Item)

    $Tenant = Get-Tenants -TenantFilter $Item.customerId
    $DomainName = $Tenant.defaultDomainName
    $TenantId = $Tenant.customerId
    $Table = Get-CIPPTable -TableName 'cacheTeamsVoice'

    try {
        $Users = (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users?`$top=999&`$select=id,userPrincipalName,displayName" -tenantid $DomainName)
        $Skip = 0
        $GraphRequest = do {
            $Results = New-TeamsAPIGetRequest -uri "https://api.interfaces.records.teams.microsoft.com/Skype.TelephoneNumberMgmt/Tenants/$($TenantId)/telephone-numbers?skip=$($Skip)&locale=en-US&top=999" -tenantid $DomainName
            $data = $Results.TelephoneNumbers | ForEach-Object {
                $CompleteRequest = $_ | Select-Object *, @{Name = 'AssignedTo'; Expression = { @($Users | Where-Object -Property id -EQ $_.TargetId) } }
                if ($CompleteRequest.AcquisitionDate) {
                    $CompleteRequest.AcquisitionDate = $_.AcquisitionDate -split 'T' | Select-Object -First 1
                } else {
                    $CompleteRequest | Add-Member -NotePropertyName 'AcquisitionDate' -NotePropertyValue 'Unknown' -Force
                }
                $CompleteRequest.AssignedTo ? $null : ($CompleteRequest | Add-Member -NotePropertyName 'AssignedTo' -NotePropertyValue 'Unassigned' -Force)
                $CompleteRequest
            }
            $Skip = $Skip + 999
            $Data
        } while ($data.Count -eq 999)

        $GraphRequest = $GraphRequest | Where-Object { $_.TelephoneNumber }

        foreach ($VoiceItem in $GraphRequest) {
            $GUID = (New-Guid).Guid
            $PolicyData = @{
                TelephoneNumber      = $VoiceItem.TelephoneNumber
                AcquiredCapabilities = $VoiceItem.AcquiredCapabilities
                AssignmentStatus     = $VoiceItem.AssignmentStatus
                AssignedTo           = $VoiceItem.AssignedTo
                NumberType           = $VoiceItem.NumberType
                IsoCountryCode       = $VoiceItem.IsoCountryCode
                PlaceName            = $VoiceItem.PlaceName
                ActivationState      = $VoiceItem.ActivationState
                IsOperatorConnect    = $VoiceItem.IsOperatorConnect
                AcquisitionDate      = $VoiceItem.AcquisitionDate
                TargetId             = $VoiceItem.TargetId
                Tenant               = $DomainName
            }
            $Entity = @{
                Policy       = [string]($PolicyData | ConvertTo-Json -Depth 10 -Compress)
                RowKey       = [string]$GUID
                PartitionKey = 'TeamsVoice'
                Tenant       = [string]$DomainName
            }
            Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force | Out-Null
        }

    } catch {
        $GUID = (New-Guid).Guid
        $ErrorPolicy = ConvertTo-Json -InputObject @{
            Tenant      = $DomainName
            displayName = "Could not connect to Tenant: $($_.Exception.Message)"
            id          = 'Error'
        } -Compress
        $Entity = @{
            Policy       = [string]$ErrorPolicy
            RowKey       = [string]$GUID
            PartitionKey = 'TeamsVoice'
            Tenant       = [string]$DomainName
        }
        Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force | Out-Null
    }
}
