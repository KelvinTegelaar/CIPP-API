param($tenant)
$Table = Get-CIPPTable -Table SchedulerConfig
if ($Tenant.tag -eq 'AllTenants') {
    $Alerts = Get-AzTableRow -Table $table -RowKey 'AllTenants' -PartitionKey 'Alert'
}
else {
    $Alerts = Get-AzTableRow -Table $table -RowKey $Tenant.tenantid -PartitionKey 'Alert'

}
$DeltaTable = Get-CIPPTable -Table DeltaCompare
$LastRunTable = Get-CIPPTable -Table AlertLastRun

$ShippedAlerts = switch ($Alerts) {
    { $_.'AdminPassword' -eq $true } {
        try {
            New-GraphGETRequest -uri "https://graph.microsoft.com/beta/roleManagement/directory/roleAssignments?`$filter=roleDefinitionId eq '62e90394-69f5-4237-9190-012177145e10'" -tenantid $($tenant.tenant) | ForEach-Object { 
                $LastChanges = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/users/$($_.principalId)?`$select=UserPrincipalName,lastPasswordChangeDateTime" -tenant $($tenant.tenant)
                if ([datetime]$LastChanges.LastPasswordChangeDateTime -gt (Get-Date).AddDays(-1)) { "Admin password has been changed for $($LastChanges.UserPrincipalName) in last 24 hours" }
            }

        }
        catch {
            "Could not get admin password changes for $($Tenant.tenant): $($_.Exception.message)"

        }
    }
    { $_.'DefenderMalware' -eq $true } {
        try {
            New-GraphGetRequest -uri "https://graph.microsoft.com/beta/tenantRelationships/managedTenants/windowsDeviceMalwareStates?`$top=999&`$filter=tenantId eq '$($Tenant.tenantid)'" | Where-Object { $_.malwareThreatState -eq 'Active' } | ForEach-Object {
                "$($_.managedDeviceName): Malware found and active. Severity: $($_.MalwareSeverity). Malware name: $($_.MalwareDisplayName)"
            }
        }
        catch {

        }
    }
    
    { $_.'DefenderStatus' -eq $true } {
        try {
            New-GraphGetRequest -uri "https://graph.microsoft.com/beta/tenantRelationships/managedTenants/windowsProtectionStates?`$top=999&`$filter=tenantId eq '$($Tenant.tenantid)'" | Where-Object { $_.realTimeProtectionEnabled -eq $false -or $_.MalwareprotectionEnabled -eq $false } | ForEach-Object {
                "$($_.managedDeviceName) - Real Time Protection: $($_.realTimeProtectionEnabled) & Malware Protection: $($_.MalwareprotectionEnabled)"
            }
        }
        catch {
    
        }
    }
    { $_.'MFAAdmins' -eq $true } {
        try {
            $AdminIds = (New-GraphGETRequest -uri "https://graph.microsoft.com/beta/roleManagement/directory/roleAssignments?`$filter=roleDefinitionId eq '62e90394-69f5-4237-9190-012177145e10'&expand=principal" -tenantid $($tenant.tenant)).principal
            $AdminList = Get-CIPPMSolUsers -tenant $tenant.tenant | Where-Object -Property ObjectID -In $AdminIds.id
            $StrongMFAMethods = '#microsoft.graph.fido2AuthenticationMethod', '#microsoft.graph.phoneAuthenticationMethod', '#microsoft.graph.passwordlessmicrosoftauthenticatorauthenticationmethod', '#microsoft.graph.softwareOathAuthenticationMethod', '#microsoft.graph.microsoftAuthenticatorAuthenticationMethod'
            $AdminList | Where-Object { $_.Usertype -eq 'Member' -and $_.BlockCredential -eq $false } | ForEach-Object {
                try {               
                (New-GraphGETRequest -uri "https://graph.microsoft.com/beta/users/$($_.ObjectID)/authentication/Methods" -tenantid $($tenant.tenant)) | ForEach-Object {
                        if ($_.'@odata.type' -in $StrongMFAMethods -and !$CARegistered) { 
                            $CARegistered = $true; 
                        } }
                    if ($_.StrongAuthenticationRequirements.StrongAuthenticationRequirement.state -eq $null -and $CARegistered -ne $true) { "Admin $($_.UserPrincipalName) is enabled but does not have any form of MFA configured." }
                }
                catch {
                    $CARegistered = $false
                }
            }
        }
        catch {
            "Could not get MFA status for admins for $($Tenant.tenant): $($_.Exception.message)"

        }
    }
    { $_.'MFAAlertUsers' -eq $true } {
        try {
            $users = Get-CIPPMSolUsers -tenant $tenant.tenant
            $StrongMFAMethods = '#microsoft.graph.fido2AuthenticationMethod', '#microsoft.graph.phoneAuthenticationMethod', '#microsoft.graph.passwordlessmicrosoftauthenticatorauthenticationmethod', '#microsoft.graph.softwareOathAuthenticationMethod', '#microsoft.graph.microsoftAuthenticatorAuthenticationMethod'

            $users | Where-Object { $_.Usertype -eq 'Member' -and $_.BlockCredential -eq $false } | ForEach-Object {
                try {
                (New-GraphGETRequest -uri "https://graph.microsoft.com/beta/users/$($_.ObjectID)/authentication/Methods" -tenantid $($tenant.tenant)) | ForEach-Object {
                        if ($_.'@odata.type' -in $StrongMFAMethods -and !$CARegistered) { 
                            $CARegistered = $true; 
                        } }
                    if ($_.StrongAuthenticationRequirements.StrongAuthenticationRequirement.state -eq $null -and $CARegistered -eq $false) { "User $($_.UserPrincipalName) is enabled but does not have any form of MFA configured." }
                }
                catch {
                    $CARegistered = $false
                }
            }

        }
        catch {
            "Could not get MFA status for users for $($Tenant.tenant): $($_.Exception.message)"

        }
    }

    { $_.'NewRole' -eq $true } {
        try {
            $AdminDelta = (Get-AzTableRow -Table $Deltatable -RowKey $Tenant.tenantid -PartitionKey 'AdminDelta').delta | ConvertFrom-Json -ErrorAction SilentlyContinue
            $NewDelta = (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/directoryRoles?`$expand=members" -tenantid $Tenant.tenant) | Select-Object displayname, Members | ForEach-Object {
                [PSCustomObject]@{
                    GroupName = $_.displayname
                    Members   = $_.Members.UserPrincipalName
                }
            }
            $NewDeltatoSave = $NewDelta | ConvertTo-Json -Depth 10 -Compress -ErrorAction SilentlyContinue
            $null = Add-AzTableRow -Table $DeltaTable -PartitionKey 'AdminDelta' -RowKey $Tenant.tenantid -property @{delta = $NewDeltatoSave } -UpdateExisting
        
            if ($AdminDelta) {
                foreach ($Group in $NewDelta) {
                    $OldDelta = $AdminDelta | Where-Object { $_.GroupName -eq $Group.GroupName }
                    $Group.members | Where-Object { $_ -notin $OldDelta.members } | ForEach-Object {
                        "$_ has been added to the $($Group.GroupName) Role"
                    }
                }
            }
        }
        catch {
            "Could not get get role changes for $($Tenant.tenant): $($_.Exception.message)"

        }
    }
    { $_.'QuotaUsed' -eq $true } {
        try {
            New-GraphGetRequest -uri "https://graph.microsoft.com/beta/reports/getMailboxUsageDetail(period='D7')?`$format=application/json" -tenantid $Tenant.tenant | ForEach-Object {
                $PercentLeft = [math]::round($_.StorageUsedInBytes / $_.prohibitSendReceiveQuotaInBytes * 100)
                if ($PercentLeft -gt 90) { "$($_.UserPrincipalName): Mailbox has less than 10% space left. Mailbox is $PercentLeft% full" }
            }
        }
        catch {
    
        }
    }
    { $_.'UnusedLicenses' -eq $true } {
        try {
            #$ConvertTable = Import-Csv Conversiontable.csv
            $ExcludedSkuList = Get-AzTableRow -Table (Get-CIPPTable -TableName ExcludedLicenses)
            New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/subscribedSkus' -tenantid $Tenant.tenant | ForEach-Object {
                $skuid = $_
                foreach ($sku in $skuid) {
                    if ($sku.skuId -in $ExcludedSkuList.guid) { continue }
                    $PrettyName = ($ConvertTable | Where-Object { $_.guid -eq $sku.skuid }).'Product_Display_Name' | Select-Object -Last 1
                    if (!$PrettyName) { $PrettyName = $skuid.skuPartNumber }

                    if ($sku.prepaidUnits.enabled - $sku.consumedUnits -ne 0) {
                        "$PrettyName has unused licenses. Using $($sku.consumedUnits) of $($sku.prepaidUnits.enabled)."
                    }
                }
            }
        }
        catch {
    
        }
    }
    { $_.'AppSecretExpiry' -eq $true } {
        try {
            $LastRun = Get-AzTableRow -Table $LastRunTable -RowKey 'AppSecretExpiry' -PartitionKey $Tenant.tenantid
            if ($null -eq $LastRun.TableTimestamp -or ($LastRun.TableTimestamp -lt (Get-Date).AddDays(-1))) {
                New-GraphGetRequest -uri "https://graph.microsoft.com/beta/applications?`$select=appId,displayName,passwordCredentials" -tenantid $Tenant.tenant | ForEach-Object {
                    foreach ($App in $_) {
                        if ($App.passwordCredentials) {
                            foreach ($Credential in $App.passwordCredentials) {
                                if ($Credential.endDateTime -lt (Get-Date).AddDays(30) -and $Credential.endDateTime -gt (Get-Date).AddDays(-7)) {
                                    "Application '{0}' has secrets expiring on {1}" -f $App.displayName, $Credential.endDateTime
                                }
                            }
                        }
                    }
                }
                $null = Add-AzTableRow -Table $LastRunTable -RowKey 'AppSecretExpiry' -PartitionKey $Tenant.tenantid -UpdateExisting
            }
        }
        catch {

        }
    }
}

$Table = Get-CIPPTable
$PartitionKey = Get-Date -UFormat '%Y%m%d'
$currentlog = Get-AzTableRow -Table $table -PartitionKey $PartitionKey 

$ShippedAlerts | ForEach-Object {
    if ($_ -notin $currentlog.Message) {
        Log-Request -message $_ -API 'Alerts' -tenant $tenant.tenant -sev Alert
    }
}
[PSCustomObject]@{
    ReturnedValues = $true
}